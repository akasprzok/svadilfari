defmodule Svadilfari do
  @moduledoc ~S"""
  A logger backend that logs messages to Grafana Loki.

  ## Options

    * `:level` - the level to be logged by this backend.
      Note that messages are filtered by the general
      `:level` configuration for the `:logger` application first.

    * `:format` - the format message used to print logs.
      Defaults to: `"\n$time $metadata[$level] $message\n"`.
      It may also be a `{module, function}` tuple that is invoked
      with the log level, the message, the current timestamp and
      the metadata and must return `t:IO.chardata/0`. See
      `Logger.Formatter`.

    * `:metadata` - the metadata to be printed by `$metadata`.
      Defaults to an empty list (no metadata).
      Setting `:metadata` to `:all` prints all metadata. See
      the "Metadata" section for more information.

    * `:max_buffer` - maximum events to buffer while waiting
      for the client to successfully send the logs to Grafana Loki.
      Once the buffer is full, the backend will block until
      a confirmation is received.

    * `:labels` - A list of {String.t, String.t} tuples that represents Grafana Loki labels.

    * `:derived_labels`: A `{module, function}` tuple that is invoked
      with the log level, the message, the current timestamp and
      the metadata and must return a list of {String.t, String.t} tuples
      which will be merged into :labels, overwriting existing keys.

    * `:client` - a keyword list of the following options:
      * `url` - The URL to which logs should be pushed. The `loki/api/v1/push` path is inferred
        and does not need to be specified.
      * `opts` - Svadilfari uses Sleipnir's `Sleipnir.Client.Tesla` client under the hood.
        Opts can be passed to it here.

  Here's an example of how to configure the `Svadilfari` backend in a
  `config/config.exs` file:

      config :logger, :backends, [:console, Svadilfari]

      config :logger, :svadilfari,
        format: "\n$time $metadata[$level] $message\n",
        metadata: [:user_id]

  ## Derived Labels

  The `:derived_labels` option can be used to derive labels at runtime, with the log as input.

  For example, to use the log level as an additional label, first write a function:

      defmodule ExampleModule do
        def level(level, _message, {_date, _time}, _metadata) do
          [{"level", Atom.to_string(level)}]
        end
      end

  and specify the function in the option:

      config :logger, :svadilfari,
        derived_labels: {ExampleModule, :level}

  Other use cases include
  * querying data from other endpoints, such as AWS EC2 metadata, to add to labels.
    These should be cached as the function is invoked for every log.
  * extracting certain metadata fields into labels. Make sure cardinality is bounded,
    for a high number of possible label combinations will blow up the size of Loki's index.
  """

  @behaviour :gen_event

  alias Sleipnir.Client.Tesla, as: TeslaClient

  @default_level nil
  @default_format Logger.Formatter.compile(nil)
  @default_max_buffer 100
  @default_metadata []
  @default_url "http://localhost:3100"

  @type labels :: list({String.t(), String.t()})

  @type t :: %__MODULE__{
          buffer: %{labels => [Sleipnir.entry()]},
          buffer_size: non_neg_integer(),
          format: term(),
          level: Logger.level(),
          max_buffer: non_neg_integer(),
          metadata: Keyword.t(),
          labels: labels(),
          derived_labels: {module(), atom()},
          client: struct(),
          ref: reference(),
          output: term()
        }

  @enforce_keys [
    :labels,
    :client
  ]

  defstruct buffer: %{},
            buffer_size: 0,
            format: @default_format,
            level: @default_level,
            max_buffer: @default_max_buffer,
            metadata: @default_metadata,
            labels: nil,
            derived_labels: {__MODULE__, :no_derived_labels},
            client: nil,
            ref: nil,
            output: nil

  @impl true
  def init(__MODULE__) do
    config = Application.get_env(:logger, :svadilfari)
    {:ok, do_init(config)}
  end

  def init({__MODULE__, opts}) when is_list(opts) do
    config = configure_merge(Application.get_env(:logger, :svadilfari), opts)
    {:ok, do_init(config)}
  end

  @impl true
  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(options, state)}
  end

  @impl true
  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    %{level: log_level, buffer_size: buffer_size, max_buffer: max_buffer} = state

    {:erl_level, level} = List.keyfind(md, :erl_level, 0, {:erl_level, level})

    cond do
      not meet_level?(level, log_level) ->
        {:ok, state}

      is_nil(state.ref) ->
        {:ok, log_event(level, msg, ts, md, state)}

      buffer_size < max_buffer ->
        {:ok, buffer_event(level, msg, ts, md, state)}

      buffer_size === max_buffer ->
        state = buffer_event(level, msg, ts, md, state)
        {:ok, await_io(state)}
    end
  end

  def handle_event(:flush, state) do
    {:ok, flush(state)}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:io_reply, ref, msg}, %{ref: ref} = state) do
    {:ok, handle_io_reply(msg, state)}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  ## Helpers

  defp meet_level?(_lvl, nil), do: true

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp configure(opts, state) do
    config = configure_merge(Application.get_env(:logger, :svadilfari), opts)
    Application.put_env(:logger, :svadilfari, config)
    do_init(config, state)
  end

  defp to_config(opts) do
    level = Keyword.get(opts, :level, @default_level)
    format = opts |> Keyword.get(:format) |> Logger.Formatter.compile()
    metadata = Keyword.get(opts, :metadata, @default_metadata) |> configure_metadata()
    max_buffer = Keyword.get(opts, :max_buffer, @default_max_buffer)
    labels = Keyword.fetch!(opts, :labels)
    derived_labels = Keyword.get(opts, :derived_labels, {__MODULE__, :no_derived_labels})

    client =
      Keyword.fetch!(opts, :client)
      |> case do
        client when is_struct(client) ->
          client

        client_opts when is_list(client_opts) ->
          opts = Keyword.get(client_opts, :opts, [])

          client_opts
          |> Keyword.get(:url, @default_url)
          |> TeslaClient.new(opts)
      end

    [
      level: level,
      format: format,
      metadata: metadata,
      max_buffer: max_buffer,
      labels: labels,
      derived_labels: derived_labels,
      client: client
    ]
  end

  defp do_init(opts, state \\ nil) do
    config = to_config(opts)

    case state do
      nil -> Kernel.struct!(__MODULE__, config)
      term -> Kernel.struct!(term, config)
    end
  end

  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp configure_merge(env, options) do
    Keyword.merge(env, options, fn
      _, _v1, v2 -> v2
    end)
  end

  defp log_event(level, msg, ts, md, state) do
    {labels, entry} = format_entry(level, msg, ts, md, state)
    output = %{labels => [entry]}
    %{state | ref: async_io(state.client, output), output: output}
  end

  defp buffer_event(level, msg, ts, md, state) do
    %{buffer: buffer, buffer_size: buffer_size} = state
    {labels, entry} = format_entry(level, msg, ts, md, state)
    buffer = Map.update(buffer, labels, [entry], fn entries -> [entry | entries] end)
    %{state | buffer: buffer, buffer_size: buffer_size + 1}
  end

  defp async_io(client, output) do
    request =
      output
      |> Enum.map(fn {labels, entries} -> entries |> Enum.reverse() |> Sleipnir.stream(labels) end)
      |> Sleipnir.request()

    Svadilfari.Async.send(client, self(), request)
  end

  defp await_io(%{ref: nil} = state), do: state

  defp await_io(%{ref: ref} = state) do
    receive do
      {:io_reply, ^ref, :ok} -> handle_io_reply(:ok, state)
      {:io_reply, ^ref, error} -> handle_io_reply(error, state) |> await_io()
    end
  end

  # Returns a tuple containg the labels for an entry, and the entry itself
  defp format_entry(level, msg, ts, md, state) do
    timestamp = Sleipnir.Timestamp.from(ts)

    entry =
      level
      |> format_event(msg, ts, md, state)
      |> Sleipnir.entry(timestamp)

    {module, function} = state.derived_labels
    derived_labels = apply(module, function, [level, msg, ts, md])
    labels = merge_labels(state.labels, derived_labels)

    {labels, entry}
  end

  defp merge_labels(labels1, labels2)

  defp merge_labels(labels1, []) when is_list(labels1), do: labels1
  defp merge_labels([], labels2) when is_list(labels2), do: labels2

  defp merge_labels(labels1, labels2) when is_list(labels1) and is_list(labels2) do
    fun = fn
      {key, _value} when is_binary(key) ->
        not :lists.keymember(key, 1, labels2)

      _ ->
        raise ArgumentError,
              "expected a list of tuples as the first argument, got: #{inspect(labels1)}"
    end

    :lists.filter(fun, labels1) ++ labels2
  end

  defp format_event(level, msg, ts, md, %__MODULE__{format: format, metadata: keys}) do
    format
    |> Logger.Formatter.format(level, msg, ts, take_metadata(md, keys))
    |> IO.iodata_to_binary()
  end

  defp take_metadata(metadata, :all) do
    metadata
  end

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error -> acc
      end
    end)
  end

  defp log_buffer(%{buffer_size: 0, buffer: %{}} = state), do: state

  defp log_buffer(state) do
    %{
      state
      | ref: async_io(state.client, state.buffer),
        buffer: %{},
        buffer_size: 0,
        output: state.buffer
    }
  end

  defp handle_io_reply(:ok, state) do
    log_buffer(%{state | ref: nil, output: nil})
  end

  defp handle_io_reply(reason, _) do
    raise "failure while logging to Loki: " <> inspect(reason)
  end

  defp flush(%{ref: nil} = state), do: state

  defp flush(state) do
    state
    |> await_io()
    |> flush()
  end

  @doc false
  def no_derived_labels(_level, _message, _ts, _metadata), do: []
end
