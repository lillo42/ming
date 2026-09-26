defmodule Ming.Messaging.BaggageTest do
  use ExUnit.Case, async: true

  alias Ming.Messaging.Baggage

  # from_string/1 is not implemented yet; only to_string/1 is covered.

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
end
