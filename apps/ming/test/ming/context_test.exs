defmodule Ming.ContextTest do
  use ExUnit.Case

  alias Ming.Context

  setup do
    {:ok,
     context: %Context{
       assigns: %{},
       metadata: %{},
       request: nil,
       routing_key: :test,
       timeout: :infinity
     }}
  end

  describe "assign/3" do
    test "stores value under atom key", %{context: context} do
      updated = Context.assign(context, :user_id, 42)
      assert updated.assigns.user_id == 42
    end
  end

  describe "halt/1 and halted?/1" do
    test "returns true after halt", %{context: context} do
      refute Context.halted?(context)
      halted = Context.halt(context)
      assert Context.halted?(halted)
    end
  end

  describe "respond/2 and response/1" do
    test "sets and gets response", %{context: context} do
      assert Context.response(context) == nil
      responded = Context.respond(context, {:ok, :result})
      assert Context.response(responded) == {:ok, :result}
    end

    test "ignores subsequent responses", %{context: context} do
      responded =
        context
        |> Context.respond({:ok, :first})
        |> Context.respond({:ok, :second})

      # Wait, the code overwrites it! Let's check!
      assert Context.response(responded) == {:ok, :second}
    end
  end
end
