defmodule SvadilfariTest do
  use ExUnit.Case
  doctest Svadilfari

  test "greets the world" do
    assert Svadilfari.hello() == :world
  end
end
