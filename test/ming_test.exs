defmodule MingTest do
  use ExUnit.Case
  doctest Ming

  describe "post/3" do
    test "send with sucess" do
      res = Ming.post(%{test: "test"})
      assert :ok == res
    end

    test "should return error when routing_key is not config" do
      res = Ming.post(%{test: "test", routing_key: "abc"})
      assert {:error, :message_producer_not_found} == res
    end
  end
end
