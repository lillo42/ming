defmodule Ming.ContextTest do
  use ExUnit.Case, async: true

  alias Ming.Context

  setup do
    {:ok,
     context: %Context{
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

  describe "respond/2 and response/1" do
    test "sets and gets response", %{context: context} do
      assert Context.response(context) == nil
      responded = Context.respond(context, {:ok, :result})
      assert Context.response(responded) == {:ok, :result}
    end

    test "later responses overwrite earlier ones", %{context: context} do
      responded =
        context
        |> Context.respond({:ok, :first})
        |> Context.respond({:ok, :second})

      assert Context.response(responded) == {:ok, :second}
    end
  end
end
