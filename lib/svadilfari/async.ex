defmodule Svadilfari.Async do
  @moduledoc """
  Handles async requests to Loki
  """
  use Task

  def send(client, pid, ref, output, labels) do
    Task.Supervisor.async(Svadilfari.TaskSupervisor, fn ->
      :telemetry.span(
        [:svadilfari, :request],
        %{buffer_size: length(output)},
        fn ->
          request =
            output
            |> Enum.reverse()
            |> Sleipnir.stream(labels)
            |> Sleipnir.request()

          {:ok, %{status: 204}} = Sleipnir.push(client, request)
          send(pid, {:io_reply, ref, :ok})
          {:ok, %{}}
        end
      )
    end)
  end
end
