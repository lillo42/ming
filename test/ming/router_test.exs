defmodule Ming.RouteTest do
  use ExUnit.Case

  doctest Ming.Router

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

    test "an event" do
      resp = Ming.ReturningOkWithDelayRouter.send(%Ming.ExampleEvent1{})
      assert resp == {:error, :more_than_one_handler_found}
    end

    test "a not register command" do
      resp = Ming.ReturningOkWithDelayRouter.send(%Ming.ExampleCommand2{}, application: :test)
      assert resp == {:error, :unregistered_command}
    end

    test "a hanlder with a timeout" do
      resp = Ming.ReturningOkWithDelayRouter.send(%Ming.ExampleCommand1{value: 300}, 200)
      assert resp == {:error, :too_many_attempts}
    end

    test "a hanlder with a timeout with a max retry" do
      resp =
        Ming.ReturningOkWithDelayRouter.send(%Ming.ExampleCommand1{value: 300},
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
  end

  describe "publish/2" do
    test "a handler returning []" do
      resp = Ming.ReturningEmptyListRouter.publish(%Ming.ExampleEvent1{})
      assert resp == :ok

      resp = Ming.ReturningEmptyListRouter.publish(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "a handler returning nil" do
      resp = Ming.ReturningNilRouter.publish(%Ming.ExampleEvent1{})
      assert resp == :ok

      resp = Ming.ReturningNilRouter.publish(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "a handler returning ok" do
      resp = Ming.ReturningOkRouter.publish(%Ming.ExampleEvent1{})
      assert resp == :ok

      resp = Ming.ReturningOkRouter.publish(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "a handler returning a non []" do
      resp = Ming.ReturningNonEmptyListRouter.publish(%Ming.ExampleEvent1{}, returning: :events)
      assert resp == :ok

      resp = Ming.ReturningNonEmptyListRouter.publish(%Ming.ExampleCommand1{}, returning: :events)
      assert resp == :ok
    end

    test "a not register event" do
      resp = Ming.ReturningOkWithDelayRouter.publish(%Ming.ExampleCommand2{})
      assert resp == :ok
    end

    test "a hanlder with a timeout" do
      resp = Ming.ReturningOkWithDelayRouter.publish(%Ming.ExampleCommand1{value: 300}, 200)
      assert resp == {:error, [:too_many_attempts]}

      resp = Ming.ReturningOkWithDelayRouter.publish(%Ming.ExampleEvent1{value: 300}, 200)
      assert resp == {:error, [:too_many_attempts]}
    end

    test "a hanlder with a timeout with a max retry" do
      resp =
        Ming.ReturningOkWithDelayRouter.publish(%Ming.ExampleCommand1{value: 300},
          timeout: 200,
          retry_attempts: 2
        )

      assert resp == {:error, [:too_many_attempts]}

      resp =
        Ming.ReturningOkWithDelayRouter.publish(%Ming.ExampleEvent1{value: 300},
          timeout: 200,
          retry_attempts: 2
        )

      assert resp == {:error, [:too_many_attempts]}
    end

    test "a handler returning error" do
      resp = Ming.ReturningErrorRouter.publish(%Ming.ExampleCommand1{value: "error"})
      assert resp == {:error, [:some_error]}

      resp = Ming.ReturningErrorRouter.publish(%Ming.ExampleEvent1{value: "error"})
      assert resp == {:error, [:some_error]}
    end

    test "a handler raising" do
      resp = Ming.RaiseRouter.publish(%Ming.ExampleCommand1{value: "throwing"})
      assert {:error, [%ArgumentError{message: "invalid val: throwing"}]} == resp

      resp = Ming.RaiseRouter.publish(%Ming.ExampleEvent1{value: "throwing"})
      assert {:error, [%ArgumentError{message: "invalid val: throwing"}]} == resp
    end

    test "a handler throwing" do
      resp = Ming.ThrowRouter.publish(%Ming.ExampleCommand1{value: "thrown"})
      assert {:error, ["thrown"]} == resp

      resp = Ming.ThrowRouter.publish(%Ming.ExampleEvent1{value: "thrown"})
      assert {:error, ["thrown", "thrown"]} == resp
    end

    test "concurrent publish with error handlers" do
      resp =
        Ming.ConcurrentPublishRouter.publish(%Ming.ExampleEvent1{value: "error"})

      assert resp == {:error, [:some_error]}
    end

    test "custom function is preserved in publish opts" do
      resp = Ming.CustomFunctionRouter.publish(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "before_execute rejects command" do
      resp = Ming.BeforeExecuteRouter.send(%Ming.ExampleCommand1{value: "reject"})
      assert resp == {:error, :rejected}
    end

    test "before_execute allows command" do
      resp = Ming.BeforeExecuteRouter.send(%Ming.ExampleCommand1{value: "ok"})
      assert resp == :ok
    end

    test "returning :execution_result" do
      resp = Ming.ExecutionResultRouter.send(%Ming.ExampleCommand1{}, returning: :execution_result)
      assert {:ok, %Ming.ExecutionResult{events: [:some_reply], metadata: %{}}} = resp
    end
  end

  describe "tracking middleware" do
    test "after_dispatch is called on success" do
      resp = Ming.TrackingRouter.send(%Ming.ExampleCommand1{})
      assert resp == :ok
    end

    test "after_failure is called on error" do
      resp = Ming.TrackingRouter.publish(%Ming.ExampleEvent1{value: "error"})
      assert {:error, [:some_error]} = resp
    end
  end
end
