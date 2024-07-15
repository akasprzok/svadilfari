defmodule Svadilfari.LoggerHandlerTest do
  use ExUnit.Case
  require Logger
  alias Sleipnir.Client.Test, as: TestClient

  @handler_name :svadilfari_handler
  setup :add_handler

  test "logs something" do
    Logger.info("Some log")
    assert_receive {:push, info_request}, :timer.seconds(1)

    [stream] = info_request.streams
    [entry] = stream.entries
    assert entry.line =~ "Some log"
  end

  defp add_handler(_context) do
    client = %TestClient{pid: self(), delay_ms: 500}
    config = %{client: client}
    assert :ok = :logger.add_handler(@handler_name, Svadilfari.LoggerHandler, config)

    on_exit(fn ->
      _ = :logger.remove_handler(@handler_name)
    end)
  end
end
