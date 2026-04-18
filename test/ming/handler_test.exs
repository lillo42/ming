defmodule Ming.HandlerTest do
  use ExUnit.Case

  alias Ming.ExecutionContext
  alias Ming.Handler

  describe "execute/3" do
    test "returns ok on successful handler" do
      context = %ExecutionContext{
        request: %Ming.ExampleCommand1{},
        handler: Ming.ReturningOkHandler,
        function: :execute
      }

      assert Handler.execute(:test, context, 5_000) == {:ok, []}
    end

    test "returns error when handler raises" do
      context = %ExecutionContext{
        request: %Ming.ExampleCommand1{value: "bad"},
        handler: Ming.RaiseHandler,
        function: :execute
      }

      assert {:error, %ArgumentError{}, _stacktrace} = Handler.execute(:test, context, 5_000)
    end

    test "returns timeout error when handler exceeds timeout" do
      context = %ExecutionContext{
        request: %Ming.ExampleCommand1{value: 500},
        handler: Ming.ReturningOkWithDelayHandler,
        function: :execute
      }

      assert Handler.execute(:test, context, 50) == {:error, :handler_execution_timeout}
    end

    test "returns error on handler returning {:error, reason}" do
      context = %ExecutionContext{
        request: %Ming.ExampleCommand1{value: "error"},
        handler: Ming.ReturningErrorHandler,
        function: :execute
      }

      assert Handler.execute(:test, context, 5_000) == {:error, :some_error}
    end
  end
end
