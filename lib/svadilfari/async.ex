defmodule Svadilfari.Async do
  @moduledoc """
  Handles async requests to Loki
  """
  use Task

  def send(client, pid, ref, request) do
    Task.Supervisor.async(Svadilfari.TaskSupervisor, fn ->
      {:ok, %{status: 204}} = Sleipnir.push(client, request)
      send(pid, {:io_reply, ref, :ok})
    end)
  end
end
