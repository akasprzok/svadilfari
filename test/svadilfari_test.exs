defmodule SvadilfariTest do
  use ExUnit.Case
  doctest Svadilfari

  require Logger

  alias Logproto.{PushRequest, StreamAdapter, EntryAdapter}

  setup do
    labels = [
      {"service", "loki"},
      {"cluster", "us-east-1"}
    ]

    bypass = Bypass.open()

    :ok =
      Logger.configure_backend(
        Svadilfari,
        metadata: [:user_id],
        labels: labels,
        client: Sleipnir.Client.Tesla.new("http://localhost:#{bypass.port}/"),
        max_buffer: 3
      )

    pid = self()

    Bypass.expect(bypass, "POST", "/loki/api/v1/push", fn conn ->
      lines = conn |> unpack_request() |> capture_lines()
      send(pid, {:lines, lines})
      Plug.Conn.resp(conn, 204, "")
    end)

    {:ok, labels: labels, bypass: bypass}
  end

  test "configures format" do
    Logger.configure_backend(Svadilfari, format: "$message [$level]")
    Logger.debug("hello")

    assert_receive {:lines, lines}, 1_000
    assert lines  =~ "hello [debug]"
  end

  test "configures metadata" do
    Logger.configure_backend(Svadilfari, format: "$metadata$message", metadata: [:user_id])
    Logger.debug("hello")

    assert_receive {:lines, lines}, 1_000
    assert lines  =~ "hello"

    Logger.metadata(user_id: 11)
    Logger.metadata(user_id: 13)
    Logger.debug("hello")

    assert_receive {:lines, lines}, 1_000
    assert lines  =~ "user_id=13 hello"
  end

  test "logs initial_call as metadata" do
    Logger.configure_backend(Svadilfari, format: "$metadata$message", metadata: [:initial_call])

    Logger.debug("hello", initial_call: {Foo, :bar, 3})
    assert_receive {:lines, lines}, 1_000
    assert lines =~ "initial_call=Foo.bar/3 hello"
  end

  test "logs domain as metadata" do
    Logger.configure_backend(Svadilfari, format: "$metadata$message", metadata: [:domain])

    Logger.debug("hello", domain: [:foobar])
    assert_receive {:lines, lines}, 1_000
    assert lines =~ "domain=elixir.foobar hello"
  end

  defp unpack_request(conn) do
    {:ok, payload, _conn} = Plug.Conn.read_body(conn)
    {:ok, request} = :snappyer.decompress(payload)

    PushRequest.decode(request)
  end

  defp capture_lines(push_request) do
    push_request.streams
    |> Enum.map(fn stream -> stream.entries end)
    |> List.flatten()
    |> Enum.map(fn entry -> entry.line end)
    |> Enum.join()
  end
end
