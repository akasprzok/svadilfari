defmodule Svadilfari.LoggerHandlerTest do
  use ExUnit.Case
  require Logger
  alias Sleipnir.Client.Test, as: TestClient

  @handler_name :svadilfari_handler

  test "logs something" do
    add_handler()

    Logger.info("Some log")
    assert_receive {:push, info_request}, :timer.seconds(1)

    [stream] = info_request.streams
    [entry] = stream.entries
    assert entry.line =~ "Some log"
  end

  test "works with formatter" do
    handler_config = %{
      config: %{
        format: "$message"
      },
      formatter: {LoggerJSON.Formatters.Basic, [metadata: :all]}
    }

    add_handler(handler_config)
    Logger.info("Some log")

    assert_receive {:push, info_request}, :timer.seconds(1)
    [stream] = info_request.streams
    [entry] = stream.entries
    assert entry.line =~ ~s("message":"Some log")
  end

  defp add_handler(handler_config \\ %{config: %{}}) do
    client = %TestClient{pid: self()}

    config =
      Map.merge(
        %{
          labels: [{"env", "test"}],
          client: client
        },
        handler_config.config
      )

    handler_config =
      handler_config
      |> Map.merge(config)
      |> Map.put(:config, config)

    assert :ok = :logger.add_handler(@handler_name, Svadilfari.LoggerHandler, handler_config)

    on_exit(fn ->
      _ = :logger.remove_handler(@handler_name)
    end)
  end
end
