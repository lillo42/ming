defmodule Ming.ExecutionContextTest do
  use ExUnit.Case

  alias Ming.ExecutionContext

  describe "retry/1" do
    test "returns error when retry_attempts is nil" do
      context = %ExecutionContext{retry_attempts: nil}
      assert ExecutionContext.retry(context) == {:error, :too_many_attempts}
    end

    test "returns error when retry_attempts is 0" do
      context = %ExecutionContext{retry_attempts: 0}
      assert ExecutionContext.retry(context) == {:error, :too_many_attempts}
    end

    test "returns error when retry_attempts is negative" do
      context = %ExecutionContext{retry_attempts: -1}
      assert ExecutionContext.retry(context) == {:error, :too_many_attempts}
    end

    test "decrements retry_attempts" do
      context = %ExecutionContext{retry_attempts: 3}
      assert {:ok, %ExecutionContext{retry_attempts: 2}} = ExecutionContext.retry(context)
    end

    test "decrements to 0" do
      context = %ExecutionContext{retry_attempts: 1}
      assert {:ok, %ExecutionContext{retry_attempts: 0}} = ExecutionContext.retry(context)
    end
  end
end
