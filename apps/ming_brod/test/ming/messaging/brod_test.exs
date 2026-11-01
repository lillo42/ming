defmodule Ming.Messaging.BrodTest do
  use ExUnit.Case, async: true

  alias Ming.Messaging.Brod

  test "registry_name derives a module from the gateway name" do
    assert Brod.registry_name(:my_gateway) == Module.concat(:my_gateway, Registry)
  end

  test "buffer_name keys the buffer on the subscription :name" do
    subscription = %{gateway_name: :my_gateway, name: :reports, routing_key: "reports.generate"}
    registry = Module.concat(:my_gateway, Registry)

    assert {:via, Registry, {^registry, {:my_gateway, :reports}}} = Brod.buffer_name(subscription)
  end

  test "buffer_name falls back to the topic when the subscription has no :name" do
    registry = Module.concat(:my_gateway, Registry)

    subscription = %{gateway_name: :my_gateway, routing_key: "reports.generate"}

    assert {:via, Registry, {^registry, {:my_gateway, "reports.generate"}}} =
             Brod.buffer_name(subscription)

    subscription = %{
      gateway_name: :my_gateway,
      routing_key: "reports.generate",
      topic: "reports"
    }

    assert {:via, Registry, {^registry, {:my_gateway, "reports"}}} =
             Brod.buffer_name(subscription)
  end

  test "consumer_name keys the consumer on the subscription and the index" do
    registry = Module.concat(:my_gateway, Registry)
    subscription = %{gateway_name: :my_gateway, name: :reports, routing_key: "reports.generate"}

    assert {:via, Registry, {^registry, {:my_gateway, :reports, 2}}} =
             Brod.consumer_name(subscription, 2)
  end

  test "topic resolves the :topic option over the routing key" do
    assert Brod.topic(%{routing_key: :reports, topic: "reports-topic"}) == "reports-topic"
    assert Brod.topic(%{routing_key: :reports}) == "reports"
    assert Brod.topic(%{routing_key: "reports.generate"}) == "reports.generate"
  end
end
