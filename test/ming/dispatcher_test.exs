defmodule Ming.DispatcherTest do
  use ExUnit.Case

  alias Ming.ExecutionContext

  describe "telemetry on exception" do
    setup do
      test_pid = self()

      handler = fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach_many(
        "test-handler-#{System.unique_integer([:positive])}",
        [
          [:ming, :application, :dispatch, :start],
          [:ming, :application, :dispatch, :stop]
        ],
        handler,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-handler-#{System.unique_integer([:positive])}")
      end)

      :ok
    end

    test "emits telemetry stop when before_dispatch raises" do
      assert_raise ArgumentError, "middleware raised", fn ->
        Ming.RaiseBeforeDispatchRouter.send(%Ming.ExampleCommand1{})
      end

      assert_receive {:telemetry_event, [:ming, :application, :dispatch, :start], _measurements,
                      _metadata},
                     1_000

      assert_receive {:telemetry_event, [:ming, :application, :dispatch, :stop], _measurements,
                      %{error: %ArgumentError{message: "middleware raised"}}},
                     1_000
    end
  end

  describe "ExecutionContext.format_reply" do
    test "handles nil metadata with returning: :execution_result" do
      context = %ExecutionContext{
        metadata: nil,
        returning: :execution_result
      }

      assert {:ok, %Ming.ExecutionResult{events: [:event], metadata: %{}}} =
               ExecutionContext.format_reply({:ok, [:event]}, context)
    end

    test "handles unexpected returning value" do
      context = %ExecutionContext{
        metadata: %{},
        returning: :unexpected
      }

      assert :ok = ExecutionContext.format_reply({:ok, [:event]}, context)
    end

    test "passes through unknown reply shapes" do
      context = %ExecutionContext{metadata: %{}, returning: false}

      assert {:error, :bad} = ExecutionContext.format_reply({:error, :bad}, context)
      assert :weird = ExecutionContext.format_reply(:weird, context)
    end
  end
end
