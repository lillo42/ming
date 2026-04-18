defmodule Ming.DispatcherTest do
  use ExUnit.Case

  alias Ming.ExecutionContext

  describe "telemetry on exception" do
    test "emits telemetry stop when before_dispatch raises" do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:ming, :application, :dispatch, :start],
          [:ming, :application, :dispatch, :stop]
        ])

      assert_raise ArgumentError, "middleware raised", fn ->
        Ming.RaiseBeforeDispatchRouter.send(%Ming.ExampleCommand1{})
      end

      assert_receive {[:ming, :application, :dispatch, :start], ^ref, _measurements,
                      %{dispatcher_type: :command}},
                     1_000

      assert_receive {[:ming, :application, :dispatch, :stop], ^ref, _measurements,
                      %{error: %ArgumentError{message: "middleware raised"}}},
                     1_000

      :telemetry.detach(ref)
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
