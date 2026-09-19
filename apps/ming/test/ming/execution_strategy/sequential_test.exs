defmodule Ming.ExecutionStrategy.SequentialTest do
  use ExUnit.Case, async: true

  alias Ming.Context
  alias Ming.ExecutionStrategy.Sequential
  alias Ming.Pipeline

  defmodule TraceMiddleware do
    @behaviour Ming.Middleware

    def execute(context, name, next) do
      trace = [name | Map.get(context.assigns, :trace, [])]
      next.(Context.assign(context, :trace, trace))
    end
  end

  defp pipeline(name), do: %Pipeline{middlewares: [{TraceMiddleware, args: name}]}

  defp context do
    %Context{request: :request, routing_key: :test, timeout: :infinity}
  end

  test "returns one context per pipeline, in order" do
    assert [first, second] = Sequential.execute([pipeline(:a), pipeline(:b)], context(), [])
    assert Enum.reverse(first.assigns[:trace]) == [:a]
    assert Enum.reverse(second.assigns[:trace]) == [:b]
  end

  test "each pipeline gets a fresh copy of the context" do
    [first, second] = Sequential.execute([pipeline(:a), pipeline(:b)], context(), [])
    refute :b in first.assigns[:trace]
    refute :a in second.assigns[:trace]
  end

  test "empty pipeline list returns an empty list" do
    assert Sequential.execute([], context(), []) == []
  end
end
