defmodule Ming.Messaging.BaggageTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ming.Messaging.Baggage

  describe "to_string/1" do
    test "joins entries as key=value pairs" do
      result = Baggage.to_string(%{"user" => "alice", "tenant" => "acme"})

      assert result |> String.split(",") |> Enum.sort() == ["tenant=acme", "user=alice"]
    end

    test "stringifies non-binary values" do
      assert Baggage.to_string(%{attempts: 3}) == "attempts=3"
    end

    test "returns an empty string for an empty map" do
      assert Baggage.to_string(%{}) == ""
    end
  end

  describe "from_string/1" do
    test "returns nil for nil and an empty string" do
      assert Baggage.from_string(nil) == nil
      assert Baggage.from_string("") == nil
    end

    test "parses comma-separated key=value pairs" do
      assert Baggage.from_string("user=alice,tenant=acme") == %{
               "user" => "alice",
               "tenant" => "acme"
             }
    end

    test "tolerates whitespace around members, keys and values" do
      assert Baggage.from_string(" user = alice , tenant=acme ") == %{
               "user" => "alice",
               "tenant" => "acme"
             }
    end

    test "drops member properties" do
      assert Baggage.from_string("user=alice;priority=high;flag") == %{"user" => "alice"}
    end

    test "allows empty values" do
      assert Baggage.from_string("user=") == %{"user" => ""}
    end

    test "allows equals signs inside the value" do
      assert Baggage.from_string("query=a=b") == %{"query" => "a=b"}
    end

    test "keeps the last value of a duplicated key" do
      assert Baggage.from_string("user=alice,user=bob") == %{"user" => "bob"}
    end

    test "round-trips with to_string/1" do
      baggage = %{"user" => "alice", "tenant" => "acme", "attempts" => "3"}

      assert baggage |> Baggage.to_string() |> Baggage.from_string() == baggage
    end

    test "returns nil and logs for an invalid key" do
      log = capture_log(fn -> assert Baggage.from_string("us er=alice") == nil end)

      assert log =~ "invalid baggage header"
      assert log =~ ~s(invalid key "us er")
    end

    test "returns nil and logs for an invalid value" do
      log = capture_log(fn -> assert Baggage.from_string(~s(user=al"ice)) == nil end)

      assert log =~ "invalid baggage header"
      assert log =~ ~s(invalid value "al\\"ice")
    end

    test "returns nil and logs for a malformed entry" do
      log = capture_log(fn -> assert Baggage.from_string("user") == nil end)

      assert log =~ "invalid baggage header"
      assert log =~ ~s(malformed entry "user")
    end

    test "returns nil and logs for more than 64 entries" do
      header = 1..65 |> Enum.map_join(",", &"k#{&1}=v")

      log = capture_log(fn -> assert Baggage.from_string(header) == nil end)

      assert log =~ "invalid baggage header"
      assert log =~ "expected at most 64 entries, got 65"
    end
  end
end
