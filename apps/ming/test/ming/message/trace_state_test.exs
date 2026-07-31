defmodule Ming.Message.TraceStateTest do
  use ExUnit.Case

  alias Ming.Message.TraceState

  describe "to_string/1" do
    test "returns nil for nil" do
      assert TraceState.to_string(nil) == nil
    end

    test "serializes a map into comma-separated key=value pairs" do
      result = TraceState.to_string(%{"vendor" => "abc"})
      assert result == "vendor=abc"
    end

    test "returns non-map values unchanged" do
      assert TraceState.to_string("already-serialized") == "already-serialized"
      assert TraceState.to_string(123) == 123
    end
  end

  describe "from_string/1" do
    test "returns an empty map for nil" do
      assert TraceState.from_string(nil) == %{}
    end

    test "returns an empty map for an empty string" do
      assert TraceState.from_string("") == %{}
    end

    test "parses valid key=value pairs" do
      assert TraceState.from_string("vendor=abc,other=xyz") ==
               %{"vendor" => "abc", "other" => "xyz"}
    end

    test "ignores malformed pairs" do
      assert TraceState.from_string("vendor=abc=bad,other=xyz") == %{"other" => "xyz"}
    end

    test "ignores invalid binary data" do
      assert TraceState.from_string("<\x80\u003e") == %{}
    end
  end
end
