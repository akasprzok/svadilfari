defmodule Svadilfari.Async do
  @moduledoc false

  use Task

  def send(client, pid, ref, request) do
    Task.Supervisor.async(Svadilfari.TaskSupervisor, fn ->
      client
      |> Sleipnir.push(request)
      |> case do
        {:ok, %{status: 204}} -> send(pid, {:io_reply, ref, :ok})
        {:ok, env} -> send(pid, {:io_reply, ref, "Unexpected status #{env.status} from Loki"})
        {:error, reason} -> send(pid, {:io_reply, ref, reason})
      end
    end)
  end
end
