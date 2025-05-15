defmodule Ming.RouteTest do
  use ExUnit.Case
  doctest Ming

  describe "send/1" do
    test "a command returning :ok" do
      resp = Ming.ExampleRouter1.send(%Ming.ExampleCommand1{}, :infinity)
      assert resp == :ok
    end

    test "a event returning :error" do
      resp = Ming.ExampleRouter1.send(%Ming.ExampleEvent1{}, :infinity)
      assert resp == {:error, :more_than_one_handler_founded}
    end
  end
end
