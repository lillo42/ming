defmodule Ming.Messaging.TraceStateTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ming.Messaging.TraceState

  describe "to_string/1" do
    test "joins entries as key=value pairs" do
      result = TraceState.to_string(%{"vendor" => "abc", "env" => "prod"})

      assert result |> String.split(",") |> Enum.sort() == ["env=prod", "vendor=abc"]
    end

    test "returns an empty string for an empty map" do
      assert TraceState.to_string(%{}) == ""
    end
  end

  describe "from_string/1" do
    test "parses key=value pairs into a map" do
      assert TraceState.from_string("vendor=abc,env=prod") ==
               %{"vendor" => "abc", "env" => "prod"}
    end

    test "accepts optional whitespace around entries" do
      assert TraceState.from_string("vendor=abc , env=prod") ==
               %{"vendor" => "abc", "env" => "prod"}
    end

    test "accepts keys in the tenant@system form" do
      assert TraceState.from_string("tenant@system=value") == %{"tenant@system" => "value"}
    end

    test "accepts values containing spaces" do
      assert TraceState.from_string("vendor=a b") == %{"vendor" => "a b"}
    end

    test "warns and returns nil for values containing equals signs" do
      log = capture_log(fn -> assert TraceState.from_string("vendor=a=b") == nil end)

      assert log =~ "invalid value"
    end

    test "returns nil for nil and empty strings" do
      assert TraceState.from_string(nil) == nil
      assert TraceState.from_string("") == nil
    end

    test "warns and returns nil for malformed entries" do
      log = capture_log(fn -> assert TraceState.from_string("vendor=abc,broken") == nil end)

      assert log =~ "invalid tracestate header"
      assert log =~ "malformed entry"
    end

    test "warns and returns nil for invalid keys" do
      log = capture_log(fn -> assert TraceState.from_string("Vendor=abc") == nil end)

      assert log =~ "invalid key"
    end

    test "warns and returns nil for invalid tenant@system keys" do
      log = capture_log(fn -> assert TraceState.from_string("tenant@System=abc") == nil end)

      assert log =~ "invalid key"
    end

    test "warns and returns nil for empty values" do
      log = capture_log(fn -> assert TraceState.from_string("vendor=") == nil end)

      assert log =~ "invalid value"
    end

    test "warns and returns nil for values longer than 256 chars" do
      log =
        capture_log(fn ->
          assert TraceState.from_string("vendor=#{String.duplicate("a", 257)}") == nil
        end)

      assert log =~ "invalid value"
    end

    test "warns and returns nil for duplicate keys" do
      log = capture_log(fn -> assert TraceState.from_string("vendor=a,vendor=b") == nil end)

      assert log =~ "duplicate keys"
    end

    test "warns and returns nil for more than 32 entries" do
      header = 1..33 |> Enum.map_join(",", &"k#{&1}=v")

      log = capture_log(fn -> assert TraceState.from_string(header) == nil end)

      assert log =~ "at most 32 entries"
    end
  end

  test "round trips" do
    map = %{"vendor" => "abc", "env" => "prod"}
    assert map |> TraceState.to_string() |> TraceState.from_string() == map
  end
end
