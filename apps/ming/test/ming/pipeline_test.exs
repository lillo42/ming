defmodule Ming.PipelineTest do
  use ExUnit.Case, async: true

  alias Ming.Context
  alias Ming.Pipeline

  defmodule TraceMiddleware do
    @behaviour Ming.Middleware

    def execute(context, name, next) do
      trace = [name | Map.get(context.assigns, :trace, [])]
      next.(Context.assign(context, :trace, trace))
    end
  end

  defmodule ShortCircuitMiddleware do
    @behaviour Ming.Middleware

    def execute(context, response, _next), do: Context.respond(context, response)
  end

  defmodule SlowMiddleware do
    @behaviour Ming.Middleware

    def execute(context, delay, next) do
      Process.sleep(delay)
      next.(context)
    end
  end

  defmodule RaisingMiddleware do
    @behaviour Ming.Middleware

    def execute(_context, _args, _next), do: raise("boom")
  end

  defp context(opts \\ []) do
    %Context{
      request: :request,
      routing_key: :test,
      timeout: Keyword.get(opts, :timeout, :infinity)
    }
  end

  defp trace_of(context), do: context.assigns[:trace] |> Enum.reverse()

  describe "concat/2" do
    test "sorts middleware by :order, stable for equal orders" do
      pipeline =
        %Pipeline{middlewares: []}
        |> Pipeline.concat([
          {TraceMiddleware, args: :c, order: 2},
          {TraceMiddleware, args: :a, order: 1},
          {TraceMiddleware, args: :b, order: 1}
        ])

      assert [
               {TraceMiddleware, args: :a, order: 1},
               {TraceMiddleware, args: :b, order: 1},
               {TraceMiddleware, args: :c, order: 2}
             ] = pipeline.middlewares
    end

    test "concat with empty list is a no-op" do
      pipeline = %Pipeline{middlewares: [{TraceMiddleware, args: :a}]}
      assert Pipeline.concat(pipeline, []) == pipeline
    end
  end

  describe "run/2" do
    test "empty pipeline returns the context unchanged" do
      assert Pipeline.run(%Pipeline{middlewares: []}, context()) == context()
    end

    test "middleware runs in order, each wrapping the next" do
      pipeline = %Pipeline{
        middlewares: [
          {TraceMiddleware, args: :first},
          {TraceMiddleware, args: :second}
        ]
      }

      assert trace_of(Pipeline.run(pipeline, context())) == [:first, :second]
    end

    test "middleware can short-circuit by not calling next" do
      pipeline = %Pipeline{
        middlewares: [
          {ShortCircuitMiddleware, args: :stopped},
          {TraceMiddleware, args: :never}
        ]
      }

      result = Pipeline.run(pipeline, context())
      assert Context.response(result) == :stopped
      refute Map.has_key?(result.assigns, :trace)
    end

    test "responds {:error, :timeout} when the pipeline exceeds the timeout" do
      pipeline = %Pipeline{middlewares: [{SlowMiddleware, args: 100}]}

      assert Context.response(Pipeline.run(pipeline, context(timeout: 10))) == {:error, :timeout}
    end

    test "a crashing pipeline propagates the exit under a timeout" do
      pipeline = %Pipeline{middlewares: [{RaisingMiddleware, []}]}

      assert catch_exit(Pipeline.run(pipeline, context(timeout: 1000)))
    end
  end
end
