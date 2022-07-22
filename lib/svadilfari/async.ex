defmodule Svadilfari.Async do
  use Task

  def send(client, pid, ref, request) do
    Task.Supervisor.async(Svadilfari.TaskSupervisor, fn ->
      {:ok, %{status: 204}} = Sleipnir.push(client, request)
      send(pid, {:io_reply, ref, :ok})
    end)
  end
end
