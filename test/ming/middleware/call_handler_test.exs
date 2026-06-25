defmodule Ming.Middleware.CallHandlerTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Middleware.CallHandler

  defmodule MyHandler do
    def handle(%{val: :ok}, _ctx), do: :ok
    def handle(%{val: nil}, _ctx), do: nil
    def handle(%{val: :error}, _ctx), do: {:error, :bad}
    def handle(%{val: :ok_tuple}, _ctx), do: {:ok, :good}
    def handle(%{val: :context}, %Context{} = ctx), do: %Context{ctx | response: :context_resp}
    def handle(%{val: :custom_error_tuple}, _ctx), do: {:error, :custom, :data}
    def handle(%{val: :custom_ok_tuple}, _ctx), do: {:ok, :custom, :data}
    def handle(%{val: :raw}, _ctx), do: %{some: "map"}
  end

  setup do
    {:ok,
     context: %Context{
       assigns: %{},
       id: "1",
       correlation_id: "1",
       handler: MyHandler,
       metadata: %{},
       middlewares: [],
       request: nil,
       routing_key: :test,
       timestamp: DateTime.utc_now(),
       timeout: :infinity
     }}
  end

  test "handles :ok", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: :ok}})
    assert Context.response(ctx) == :ok
  end

  test "handles nil", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: nil}})
    assert Context.response(ctx) == {:ok, nil}
  end

  test "handles {:error, reason}", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: :error}})
    assert Context.response(ctx) == {:error, :bad}
  end

  test "handles {:ok, resp}", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: :ok_tuple}})
    assert Context.response(ctx) == {:ok, :good}
  end

  test "handles Context return", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: :context}})
    assert Context.response(ctx) == :context_resp
  end

  test "handles other error tuples", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: :custom_error_tuple}})
    assert Context.response(ctx) == {:error, :custom, :data}
  end

  test "handles other ok tuples", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: :custom_ok_tuple}})
    assert Context.response(ctx) == {:ok, :custom, :data}
  end

  test "handles raw terms", %{context: context} do
    ctx = CallHandler.before_handle(%{context | request: %{val: :raw}})
    assert Context.response(ctx) == {:ok, %{some: "map"}}
  end

  test "after_handle is a no-op", %{context: context} do
    assert CallHandler.after_handle(context) == context
  end
end
