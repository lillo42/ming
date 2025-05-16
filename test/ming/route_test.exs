defmodule Ming.RouteTest do
  use ExUnit.Case
  doctest Ming

  describe "send/1" do
    test "a handler returning []" do
      resp = Ming.ReturningEmptyListRouter.send(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "a handler returning nil" do
      resp = Ming.ReturningNilRouter.send(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "a handler returning ok" do
      resp = Ming.ReturningOkRouter.send(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "a handler returning a non []" do
      resp = Ming.ReturningNonEmptyListRouter.send(%Ming.ExampleCommand1{})
      assert resp == {:ok, [:some_reply]}
    end

    test "a event returning :error" do
      resp = Ming.ReturningEmptyListRouter.send(%Ming.ExampleEvent1{})
      assert resp == {:error, :more_than_one_handler_founded}
    end
  end
end
