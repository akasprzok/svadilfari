defmodule Svadilfari do
  @moduledoc """
  A Logger Backend for Grafana Loki.
  """

  @behaviour :gen_event

  @default_level nil
  @default_format Logger.Formatter.compile(nil)
  @default_max_buffer 100
  @default_metadata []
  @default_url "http://localhost:3100"

  @type t :: %__MODULE__{
          buffer: list(Sleipnir.entry()),
          buffer_size: non_neg_integer(),
          format: term(),
          level: Logger.level(),
          max_buffer: non_neg_integer(),
          metadata: Keyword.t(),
          labels: list({String.t(), String.t()}),
          client: struct(),
          ref: reference(),
          output: term()
        }

  @enforce_keys [
    :labels,
    :client
  ]

  defstruct buffer: [],
            buffer_size: 0,
            format: @default_format,
            level: @default_level,
            max_buffer: @default_max_buffer,
            metadata: @default_metadata,
            labels: nil,
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
    format = Logger.Formatter.compile(Keyword.get(opts, :format))
    metadata = Keyword.get(opts, :metadata, @default_metadata) |> configure_metadata()
    max_buffer = Keyword.get(opts, :max_buffer, @default_max_buffer)
    labels = Keyword.fetch!(opts, :labels)

    client =
      Keyword.fetch!(opts, :client)
      |> case do
        client when is_struct(client) ->
          client

        client_opts when is_list(client_opts) ->
          opts = Keyword.get(client_opts, :opts, [])

          client_opts
          |> IO.inspect()
          |> Keyword.get(:url, @default_url)
          |> Sleipnir.Client.Tesla.new(opts)
      end

    [
      level: level,
      format: format,
      metadata: metadata,
      max_buffer: max_buffer,
      labels: labels,
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
    output = [format_entry(level, msg, ts, md, state)]
    %{state | ref: async_io(state.client, output, state.labels), output: output}
  end

  defp buffer_event(level, msg, ts, md, state) do
    %{buffer: buffer, buffer_size: buffer_size} = state
    buffer = [format_entry(level, msg, ts, md, state) | buffer]
    %{state | buffer: buffer, buffer_size: buffer_size + 1}
  end

  defp async_io(client, output, labels) do
    ref = make_ref()

    Svadilfari.Async.send(client, self(), ref, output, labels)
    ref
  end

  defp await_io(%{ref: nil} = state), do: state

  defp await_io(%{ref: ref} = state) do
    receive do
      {:io_reply, ^ref, :ok} -> handle_io_reply(:ok, state)
      {:io_reply, ^ref, error} -> handle_io_reply(error, state) |> await_io()
    end
  end

  defp format_entry(level, msg, ts, md, state) do
    timestamp = Sleipnir.Timestamp.from(ts)

    level
    |> format_event(msg, ts, md, state)
    |> Sleipnir.entry(timestamp)
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

  defp log_buffer(%{buffer_size: 0, buffer: []} = state), do: state

  defp log_buffer(state) do
    %{
      state
      | ref: async_io(state.client, state.buffer, state.labels),
        buffer: [],
        buffer_size: 0,
        output: state.buffer
    }
  end

  defp handle_io_reply(:ok, state) do
    log_buffer(%{state | ref: nil, output: nil})
  end

  defp handle_io_reply({:error, reason}, _) do
    raise "failure while logging to Loki: " <> inspect(reason)
  end

  defp flush(%{ref: nil} = state), do: state

  defp flush(state) do
    state
    |> await_io()
    |> flush()
  end
end
