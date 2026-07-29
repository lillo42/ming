defmodule Ming.Message.BaggageTest do
  use ExUnit.Case

  alias Ming.Message.Baggage

  describe "put/3" do
    test "stores a plain value under the key" do
      assert Baggage.put(%{}, "tenant", "acme") == %{"tenant" => "acme"}
    end
  end

  describe "put/4" do
    test "stores a value with metadata" do
      assert Baggage.put(%{}, "tenant", "acme", [{"prop", "value"}]) ==
               %{"tenant" => [value: "acme", metadata: [{"prop", "value"}]]}
    end
  end

  describe "put_new/4" do
    test "stores a value when the key is absent" do
      assert Baggage.put_new(%{}, "tenant", "acme", [{"prop", "value"}]) ==
               %{"tenant" => [value: "acme", metadata: [{"prop", "value"}]]}
    end

    test "keeps the existing value when the key is present" do
      assert Baggage.put_new(%{"tenant" => "existing"}, "tenant", "acme", [{"prop", "value"}]) ==
               %{"tenant" => "existing"}
    end
  end

  describe "from_string/1" do
    test "returns an empty map for nil" do
      assert Baggage.from_string(nil) == %{}
      assert Baggage.from_string("") == %{}
    end

    test "parses a simple key=value pair" do
      assert Baggage.from_string("tenant=acme") == %{"tenant" => "acme"}
    end

    test "parses multiple comma-separated pairs" do
      assert Baggage.from_string("tenant=acme,region=eu") ==
               %{"tenant" => "acme", "region" => "eu"}
    end

    test "parses metadata as keyword list entries" do
      assert Baggage.from_string("tenant=acme;propertyId=12345") ==
               %{"tenant" => [value: "acme", metadata: [{"propertyId", "12345"}]]}
    end

    test "ignores malformed key=value segments" do
      assert Baggage.from_string("tenant=acme=extra,region=eu") == %{"region" => "eu"}
    end
  end

  describe "to_string/1" do
    test "serializes a map of plain binary values" do
      assert Baggage.to_string(%{"tenant" => "acme"}) == "tenant=acme"
    end

    test "URL-encodes binary values" do
      assert Baggage.to_string(%{"tenant" => "ac me"}) == "tenant=ac+me"
    end

    test "serializes a keyword-list value with metadata" do
      assert Baggage.to_string(%{"tenant" => [value: "acme", metadata: [{"prop", "value"}]]}) ==
               "tenant=acme;prop=value"
    end

    test "serializes a plain list of stringable values" do
      assert Baggage.to_string(%{"ids" => [1, 2, 3]}) == "ids=1,2,3"
    end

    test "returns nil for nil values" do
      assert Baggage.to_string(nil) == nil
    end

    test "drops values that cannot be converted to strings" do
      assert Baggage.to_string(%{"ok" => "value", "bad" => %{nested: "map"}}) == "ok=value"
    end

    test "returns binary values unchanged" do
      assert Baggage.to_string("raw-value") == "raw-value"
    end
  end

  describe "round-trip" do
    test "preserves plain key=value pairs" do
      original = %{"tenant" => "acme", "region" => "eu"}

      assert original
             |> Baggage.to_string()
             |> Baggage.from_string() == original
    end
  end
end
