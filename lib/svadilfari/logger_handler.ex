defmodule Svadilfari.LoggerHandler do
  @moduledoc """
  A :logger handler for elixir apps > 1.15.
  """

  @doc false
  @spec adding_handler(:logger.handler_config()) :: {:ok, :logger.handler_config()}
  def adding_handler(handler_config) do
    :ok = start_under_supervisor(handler_config.id)

    :ok =
      :gen_event.add_handler(
        {:global, Svadilfari.EventManager},
        Svadilfari,
        {Svadilfari, Enum.into(handler_config.config, [])}
      )

    {:ok, handler_config}
  end

  # @doc false
  # @spec removing_handler(:logger.handler_config()) :: :ok
  # def removing_handler(config) do
  #   :ok = terminate_and_delete(config.id)
  # end

  @doc false
  @spec log(:logger.log_event(), :logger.handler_config()) :: :ok
  def log(log_event, handler_config) do
    %{level: level, msg: _msg, meta: %{time: time, gl: gl}} = log_event
    %{formatter: {formatter, formatter_config}} = handler_config
    dt = DateTime.from_unix!(time, :microsecond)
    millisecond = trunc(elem(dt.microsecond, 0) / 10 ** elem(dt.microsecond, 1) * 10 ** 3)
    ts = {{dt.year, dt.month, dt.day}, {dt.hour, dt.minute, dt.second, millisecond}}
    md = []

    msg = formatter.format(log_event, formatter_config)

    :gen_event.sync_notify(
      {:global, Svadilfari.EventManager},
      {level, gl, {Logger, msg, ts, md}}
    )
  end

  defp start_under_supervisor(id) do
    spec = %{id: child_id(id), start: {:gen_event, :start, [{:global, Svadilfari.EventManager}]}}

    case Supervisor.start_child(Svadilfari.Supervisor, spec) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # defp terminate_and_delete(id) when is_atom(id) do
  #   _ = Supervisor.terminate_child(Svadilfari.Supervisor, child_id(id))
  #   _ = Supervisor.delete_child(Svadilfari.Supervisor, child_id(id))
  #   :ok
  # end

  defp child_id(id), do: {__MODULE__, id}
end
