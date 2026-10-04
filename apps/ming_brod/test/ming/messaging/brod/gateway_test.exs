defmodule Ming.Messaging.Brod.GatewayTest do
  use ExUnit.Case, async: false

  alias Ming.Messaging.Brod.Gateway

  defp config(overrides) do
    Map.merge(
      %{name: :brod_gateway_test, endpoints: [{~c"localhost", 9092}]},
      Map.new(overrides)
    )
  end

  test "producer/1 and consumer/1 resolve the brod modules" do
    assert Gateway.producer(%{}) == Ming.Messaging.Brod.Producer
    assert Gateway.consumer(%{}) == Ming.Messaging.Brod.Consumer
  end

  test "raises on a non-atom name" do
    assert_raise ArgumentError, ~r/expects an atom :name/, fn ->
      Gateway.start_link(config(name: "not-an-atom"))
    end
  end

  test "raises on missing or empty endpoints" do
    for endpoints <- [nil, []] do
      assert_raise ArgumentError, ~r/non-empty list of :endpoints/, fn ->
        Gateway.start_link(config(endpoints: endpoints))
      end
    end
  end

  test "raises on an entry without :topic or :routing_key" do
    assert_raise ArgumentError, ~r/without :topic or :routing_key/, fn ->
      Gateway.start_link(config(publications: [%{name: :broken}]))
    end
  end

  test "raises on an empty topic" do
    assert_raise ArgumentError, ~r/empty topic/, fn ->
      Gateway.start_link(config(publications: [%{routing_key: ""}]))
    end
  end

  test "raises on an invalid provisioner" do
    assert_raise ArgumentError, ~r/:provisioner to be one of/, fn ->
      Gateway.start_link(config(publications: [%{routing_key: :key, provisioner: :maybe}]))
    end
  end

  test "raises on a non-positive :buffer_size" do
    for size <- [0, -1, 1.5, "10"] do
      assert_raise ArgumentError, ~r/:buffer_size/, fn ->
        Gateway.start_link(
          config(subscriptions: [%{name: :sub, routing_key: :key, buffer_size: size}])
        )
      end
    end
  end
end
