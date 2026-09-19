defmodule Ming.ExecutionStrategy.ParallelTest do
  use ExUnit.Case, async: true

  alias Ming.Context
  alias Ming.ExecutionStrategy.Parallel
  alias Ming.Pipeline

  defmodule SleepMiddleware do
    @behaviour Ming.Middleware

    def execute(context, {delay, response}, _next) do
      Process.sleep(delay)
      Context.respond(context, response)
    end
  end

  defp pipeline(delay, response),
    do: %Pipeline{middlewares: [{SleepMiddleware, args: {delay, response}}]}

  defp context do
    %Context{request: :request, routing_key: :test, timeout: :infinity}
  end

  test "runs every pipeline and returns their contexts" do
    contexts = Parallel.execute([pipeline(0, :a), pipeline(0, :b)], context(), [])

    assert Enum.sort(Enum.map(contexts, &Context.response/1)) == [:a, :b]
  end

  test "runs pipelines concurrently" do
    started = System.monotonic_time(:millisecond)

    contexts = Parallel.execute([pipeline(300, :a), pipeline(300, :b)], context(), [])

    elapsed = System.monotonic_time(:millisecond) - started
    assert length(contexts) == 2
    assert elapsed < 550
  end

  test "empty pipeline list returns an empty list" do
    assert Parallel.execute([], context(), []) == []
  end
end
