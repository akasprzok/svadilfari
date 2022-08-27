defmodule SvadilfariTest do
  use ExUnit.Case
  doctest Svadilfari

  require Logger

  alias Sleipnir.Client.Test, as: TestClient

  def slow_test_client(_) do
    client = %TestClient{pid: self(), delay_ms: 500}

    :ok =
      Logger.configure_backend(
        Svadilfari,
        client: client,
        derived_labels: {Svadilfari, :no_derived_labels}
      )
  end

  describe "buffer tests" do
    setup [:slow_test_client]

    test "consolidates entries with the same labels into streams" do
      :ok =
        Logger.configure_backend(Svadilfari,
          labels: [],
          derived_labels: {__MODULE__, :level_label},
          format: "$message"
        )

      Logger.debug("hello")
      Logger.info("entry1")
      Logger.info("entry2")

      assert_receive {:push, debug_request}, :timer.seconds(1)
      assert_receive {:push, info_request}, :timer.seconds(1)

      [stream] = debug_request.streams
      assert stream.labels == ~s({level="debug"})

      [stream] = info_request.streams
      assert stream.labels == ~s({level="info"})
      [entry1, entry2] = stream.entries
      assert entry1.line == "entry1"
      assert entry2.line == "entry2"
    end
  end

  def test_client(_) do
    client = %TestClient{pid: self()}

    :ok =
      Logger.configure_backend(
        Svadilfari,
        client: client,
        derived_labels: {Svadilfari, :no_derived_labels}
      )
  end

  describe "labels" do
    setup [:test_client]

    test "are set from config" do
      :ok = Logger.configure_backend(Svadilfari, labels: [{"service", "svadilfari"}])
      Logger.debug("hello")
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      assert stream.labels == ~s({service="svadilfari"})
    end

    test "derived labels overwrite static labels" do
      :ok =
        Logger.configure_backend(Svadilfari,
          labels: [{"level", "info"}]
        )

      Logger.debug("hello")
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      assert stream.labels == ~s({level="info"})

      Logger.configure_backend(Svadilfari,
        derived_labels: {__MODULE__, :level_label}
      )

      Logger.debug("hello")
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      assert stream.labels == ~s({level="debug"})
    end

    test "can be derived from function" do
      :ok =
        Logger.configure_backend(Svadilfari,
          labels: [{"service", "svadilfari"}],
          derived_labels: {__MODULE__, :level_label}
        )

      Logger.debug("hello")
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      assert stream.labels == ~s({level="debug",service="svadilfari"})
    end

    test "like entries are grouped by labels" do
      :ok =
        Logger.configure_backend(Svadilfari,
          labels: [{"service", "svadilfari"}],
          derived_labels: {__MODULE__, :level_label}
        )

      Logger.debug("hello")
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      assert stream.labels == ~s({level="debug",service="svadilfari"})
    end
  end

  describe "logging" do
    setup [:test_client]

    test "configures format" do
      Logger.configure_backend(Svadilfari, format: "$message [$level]")
      Logger.debug("hello")

      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line == "hello [debug]"
    end

    test "configures metadata" do
      Logger.configure_backend(Svadilfari, format: "$metadata$message", metadata: [:user_id])
      Logger.debug("hello")

      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line == "hello"

      Logger.metadata(user_id: 11)
      Logger.metadata(user_id: 13)
      Logger.debug("hello2")

      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line == "user_id=13 hello2"
    end

    test "logs initial_call as metadata" do
      Logger.configure_backend(Svadilfari, format: "$metadata$message", metadata: [:initial_call])

      Logger.debug("hello", initial_call: {Foo, :bar, 3})
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line == "initial_call=Foo.bar/3 hello"
    end

    test "logs domain as metadata" do
      Logger.configure_backend(Svadilfari, format: "$metadata$message", metadata: [:domain])

      Logger.debug("hello", domain: [:foobar])
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line == "domain=elixir.foobar hello"
    end

    test "logs mfa as metadata" do
      Logger.configure_backend(Svadilfari, format: "$metadata$message", metadata: [:mfa])
      {function, arity} = __ENV__.function
      mfa = Exception.format_mfa(__MODULE__, function, arity)

      Logger.debug("hello")
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line == "mfa=#{mfa} hello"
    end

    test "configures formatter to {module, function} tuple" do
      Logger.configure_backend(Svadilfari, format: {__MODULE__, :format})

      Logger.debug("hello")
      assert_receive {:push, request}, 1_000
      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line == "my_format: hello"
    end

    test "configures metadata to :all" do
      Logger.configure_backend(Svadilfari, format: "$metadata", metadata: :all)
      Logger.metadata(user_id: 11)
      Logger.metadata(dynamic_metadata: 5)

      %{module: mod, function: {name, arity}, file: file, line: line} = __ENV__
      Logger.debug("hello")

      assert_receive {:push, request}, :timer.seconds(1)

      [stream] = request.streams
      [entry] = stream.entries
      assert entry.line =~ "file=#{file}"
      assert entry.line =~ "line=#{line + 1}"
      assert entry.line =~ "module=#{inspect(mod)}"
      assert entry.line =~ "function=#{name}/#{arity}"
      assert entry.line =~ "dynamic_metadata=5"
      assert entry.line =~ "user_id=11"
    end

    test "provides metadata defaults" do
      metadata = [:file, :line, :module, :function]
      Logger.configure_backend(Svadilfari, format: "$metadata", metadata: metadata)
      %{module: mod, function: {name, arity}, file: file, line: line} = __ENV__
      Logger.debug("hello")

      assert_receive {:push, request}, :timer.seconds(1)

      [stream] = request.streams
      [entry] = stream.entries

      assert entry.line ==
               "file=#{file} line=#{line + 1} module=#{inspect(mod)} function=#{name}/#{arity} "
    end
  end

  def format(_level, message, _ts, _metadata) do
    "my_format: #{message}"
  end

  def level_label(level, _message, _ts, _metadata) do
    [{"level", Atom.to_string(level)}]
  end
end
