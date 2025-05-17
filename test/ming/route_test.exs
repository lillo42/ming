defmodule Ming.RouteTest do
  require Logger
  use ExUnit.Case
  doctest Ming

  describe "send/2" do
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
      resp = Ming.ReturningNonEmptyListRouter.send(%Ming.ExampleCommand1{}, returning: :events)
      assert resp == {:ok, [:some_reply]}
    end

    test "a handler returning a key" do
      resp = Ming.ReturningAKeyRouter.send(%Ming.ExampleCommand1{}, returning: :events)
      assert resp == {:ok, :some_reply}
    end

    test "a event" do
      resp = Ming.ReturningOkWithDelayRouter.send(%Ming.ExampleEvent1{})
      assert resp == {:error, :more_than_one_handler_founded}
    end

    test "a hanlder with a timeout" do
      resp = Ming.ReturningOkWithDelayRouter.send(%Ming.ExampleCommand1{value: 300}, 200)
      assert resp == {:error, :too_many_attempts}
    end

    test "a hanlder with a timeout with a max retry" do
      resp =
        Ming.ReturningOkWithDelayRouter.send(%Ming.ExampleCommand1{value: 200},
          timeout: 200,
          retry_attempts: 2
        )

      assert resp == {:error, :too_many_attempts}
    end

    test "a handler returning error" do
      resp = Ming.ReturningErrorRouter.send(%Ming.ExampleCommand1{value: "error"})
      assert resp == {:error, :some_error}
    end

    test "a handler raising" do
      resp = Ming.RaiseRouter.send(%Ming.ExampleCommand1{value: "throwing"})
      assert {:error, %ArgumentError{message: "invalid val: throwing"}} == resp
    end

    # test "a handler throwing" do
    #   resp = Ming.ThrowRouter.send(%Ming.ExampleCommand1{value: "throwing"})
    #   assert resp == {:error, :some_error}
    # end
  end
end
