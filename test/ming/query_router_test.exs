defmodule Ming.QueryRouterTest do
  use ExUnit.Case

  describe "query/2" do
    test "executes registered query" do
      resp = Ming.QueryRouterTestRouter.query(%Ming.ExampleCommand1{})
      assert resp == {:ok, :query_result}
    end

    test "returns unregistered_query for unknown query" do
      resp = Ming.QueryRouterTestRouter.query(%Ming.ExampleCommand2{}, application: :ming)
      assert resp == {:error, :unregistered_query}
    end

    test "accepts timeout as integer" do
      resp = Ming.QueryRouterTestRouter.query(%Ming.ExampleCommand1{}, 5_000)
      assert resp == {:ok, :query_result}
    end

    test "accepts timeout as :infinity" do
      resp = Ming.QueryRouterTestRouter.query(%Ming.ExampleCommand1{}, :infinity)
      assert resp == {:ok, :query_result}
    end
  end
end
