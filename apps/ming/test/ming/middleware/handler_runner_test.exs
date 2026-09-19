defmodule Ming.Middleware.HandlerRunnerTest do
  use ExUnit.Case, async: true

  alias Ming.Context
  alias Ming.Middleware.HandlerRunner

  defmodule ShapeHandler do
    @behaviour Ming.Handler

    def handle(:ok, _context), do: :ok
    def handle(nil, _context), do: nil
    def handle(:ok_tuple, _context), do: {:ok, 1}
    def handle(:error_tuple, _context), do: {:error, :bad}
    def handle(:context, context), do: Context.respond(context, :from_context)
    def handle(:other, _context), do: 42
  end

  defp run(request, handler \\ ShapeHandler) do
    context = %Context{request: request, routing_key: :test, timeout: :infinity}
    next = fn _ -> raise "HandlerRunner is terminal and must not call next" end
    HandlerRunner.execute(context, handler, next)
  end

  test "keeps :ok as :ok" do
    assert Context.response(run(:ok)) == :ok
  end

  test "normalizes nil to {:ok, nil}" do
    assert Context.response(run(nil)) == {:ok, nil}
  end

  test "passes {:ok, value} and {:error, reason} through" do
    assert Context.response(run(:ok_tuple)) == {:ok, 1}
    assert Context.response(run(:error_tuple)) == {:error, :bad}
  end

  test "accepts a context returned by the handler" do
    assert Context.response(run(:context)) == :from_context
  end

  test "wraps any other value in {:ok, value}" do
    assert Context.response(run(:other)) == {:ok, 42}
  end

  test "raises ArgumentError for an invalid handler" do
    assert_raise ArgumentError, ~r/invalid handler/, fn -> run(:ok, nil) end
  end
end
