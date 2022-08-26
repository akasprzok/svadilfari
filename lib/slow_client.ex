defmodule Svadilfari.SlowClient do
  @moduledoc """
  A test client that returns what it was sent
  """
  @type t :: %__MODULE__{
          pid: pid()
        }

  defstruct [:pid]
end

defimpl Sleipnir.Client, for: Svadilfari.SlowClient do
  alias Logproto.PushRequest

  def push(client, %PushRequest{} = request, _opts \\ []) do
    :timer.sleep(500)
    send(client.pid, {:push, request})
    {:ok, %{status: 204, headers: []}}
  end
end
