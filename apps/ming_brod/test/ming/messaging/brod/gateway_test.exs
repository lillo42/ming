defmodule Ming.Messaging.Brod.GatewayTest do
  use ExUnit.Case, async: false

  alias Ming.Messaging.Brod
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

  test "starts a buffer, a subscriber and one consumer per subscription consumer" do
    config =
      config(
        subscriptions: [
          %{name: :sub, routing_key: "topic"},
          %{name: :multi, routing_key: "topic2", number_of_consumers: 3}
        ]
      )

    assert {:ok, {_flags, children}} = Gateway.init(config)

    ids = Enum.map(children, & &1.id)

    assert Enum.count(ids, &match?({Brod.Buffer, _}, &1)) == 2
    assert Enum.count(ids, &match?({:brod_group_subscriber, _}, &1)) == 2

    consumer_names = for {:consumer, name} <- ids, do: name
    assert length(consumer_names) == 4

    subscription = %{gateway_name: :brod_gateway_test, name: :multi, routing_key: "topic2"}

    for index <- 1..3 do
      assert Brod.consumer_name(subscription, index) in consumer_names
    end

    assert Brod.consumer_name(
             %{gateway_name: :brod_gateway_test, name: :sub, routing_key: "topic"},
             1
           ) in consumer_names
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
