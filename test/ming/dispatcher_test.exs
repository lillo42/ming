defmodule Ming.DispatcherTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Dispatcher
  alias Ming.Middleware.CallHandler

  defmodule SuccessHandler do
    def handle(%{val: "ok"}, _ctx), do: :ok
    def handle(%{val: "error"}, _ctx), do: {:error, :failed}
  end

  defmodule TimeoutHandler do
    def handle(%{val: delay}, _ctx) do
      Process.sleep(delay)
      :ok
    end
  end

  defmodule RaiseHandler do
    def handle(_req, _ctx) do
      raise "boom"
    end
  end

  defmodule CustomMiddleware do
    @behaviour Ming.Middleware

    def before_handle(ctx) do
      if ctx.request.val == "halt" do
        ctx |> Context.halt() |> Context.respond({:error, :halted})
      else
        Context.assign(ctx, :custom, true)
      end
    end

    def after_handle(ctx) do
      Context.assign(ctx, :after_called, true)
    end
  end

  setup do
    context = %Context{
      assigns: %{},
      id: "id",
      correlation_id: "corr",
      handler: SuccessHandler,
      metadata: %{},
      middlewares: [CallHandler],
      request: %{val: "ok"},
      routing_key: :test_key,
      timestamp: DateTime.utc_now(),
      timeout: :infinity
    }

    {:ok, context: context}
  end

  describe "dispatch/1" do
    test "executes handler successfully", %{context: context} do
      result = Dispatcher.dispatch(context)
      assert Context.response(result) == :ok
    end

    test "handles handler error response", %{context: context} do
      context = %{context | request: %{val: "error"}}
      result = Dispatcher.dispatch(context)
      assert Context.response(result) == {:error, :failed}
    end

    test "handles exceptions in handler", %{context: context} do
      context = %{context | handler: RaiseHandler}
      result = Dispatcher.dispatch(context)
      assert {:error, %RuntimeError{message: "boom"}} = Context.response(result)
      assert Context.halted?(result)
    end

    test "executes custom middleware before and after", %{context: context} do
      context = %{context | middlewares: [CustomMiddleware, CallHandler]}
      result = Dispatcher.dispatch(context)
      assert result.assigns.custom == true
      assert result.assigns.after_called == true
      assert Context.response(result) == :ok
    end

    test "middleware can halt pipeline", %{context: context} do
      context = %{context | middlewares: [CustomMiddleware, CallHandler], request: %{val: "halt"}}
      result = Dispatcher.dispatch(context)
      assert Context.halted?(result)
      assert Context.response(result) == {:error, :halted}
      # after_handle should NOT be called for CustomMiddleware because the chain halts before it
      # actually wait, it halts DURING before_handle of CustomMiddleware, so after_handle is
      # skipped for subsequent but what about itself?
      refute Map.has_key?(result.assigns, :after_called)
    end

    test "executes with timeout successfully", %{context: context} do
      context = %{context | handler: TimeoutHandler, request: %{val: 10}, timeout: 100}
      result = Dispatcher.dispatch(context)
      assert Context.response(result) == :ok
    end

    test "returns timeout error when execution exceeds timeout", %{context: context} do
      context = %{context | handler: TimeoutHandler, request: %{val: 200}, timeout: 50}
      result = Dispatcher.dispatch(context)
      assert Context.response(result) == {:error, :timeout}
      assert Context.halted?(result)
    end
  end
end
