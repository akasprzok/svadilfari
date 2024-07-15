defmodule Svadilfari.LoggerHandler do
  @moduledoc """
  A :logger handler for elixir apps > 1.15.
  """

  # Callback for :logger handlers
  # @doc false
  # @spec adding_handler(:logger.handler_config()) :: {:ok, :logger.handler_config()}
  # def adding_handler(config) do
  #   # The :config key may not be here.
  #   dbg(config)

  #   Supervisor.start_child(Svadilfari.Supervisor, Svadilfari)
  #     {:ok, config}
  #   end
  # end

  @doc false
  @spec adding_handler(:logger.handler_config()) :: {:ok, :logger.handler_config()}
  def adding_handler(config) do
    {:ok, pid} =
      Supervisor.start_child(
        Svadilfari.Supervisor,
        %{
          id: config.id,
          start: {:gen_event, :start, [{:global, Svadilfari.EventManager}]}
        }
      )

    :ok = :gen_event.add_handler(pid, Svadilfari, {Svadilfari, Enum.into(config, [])})
    {:ok, config}
  end

  @doc false
  @spec log(:logger.log_event(), :logger.handler_config()) :: :ok
  def log(log_event, _handler_config) do
    %{meta: meta, msg: msg, level: level} = log_event
    %{time: time, gl: gl} = meta
    dt = DateTime.from_unix!(time, :microsecond)
    millisecond = trunc(elem(dt.microsecond, 0) / 10 ** elem(dt.microsecond, 1) * 10 ** 3)
    ts = {{dt.year, dt.month, dt.day}, {dt.hour, dt.minute, dt.second, millisecond}}
    md = []

    :gen_event.sync_notify(
      {:global, Svadilfari.EventManager},
      {level, gl, {Logger, elem(msg, 1), ts, md}}
    )
  end
end
