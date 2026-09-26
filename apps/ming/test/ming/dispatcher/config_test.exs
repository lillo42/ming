defmodule Ming.Dispatcher.ConfigTest do
  use ExUnit.Case, async: true

  alias Ming.Dispatcher.Config

  defp defaults do
    [
      gateways: [
        kafka: %{
          adapter: KafkaAdapter,
          connection: [endpoints: [{"localhost", 9092}]],
          publications: [
            %{routing_key: :created, topic_or_queue: "orders", mapper: :json, transformers: []}
          ],
          subscriptions: [
            %{name: :orders, routing_key: :created, batch_processing: :sequential}
          ]
        }
      ],
      mapper: :json,
      timeout: :infinity
    ]
  end

  test "returns defaults when there are no overrides" do
    assert Config.merge(defaults(), []) == defaults()
  end

  test "overrides top-level options" do
    config = Config.merge(defaults(), timeout: 5_000, mapper: :protobuf)

    assert config[:timeout] == 5_000
    assert config[:mapper] == :protobuf
  end

  test "merges a gateway by name, keeping keys absent from the override" do
    config =
      Config.merge(defaults(), gateways: [kafka: [connection: [endpoints: [{"broker", 9092}]]]])

    kafka = config[:gateways][:kafka]
    assert kafka.connection == [endpoints: [{"broker", 9092}]]
    assert kafka.adapter == KafkaAdapter
  end

  test "merges publications by routing key" do
    config =
      Config.merge(defaults(),
        gateways: [kafka: [publications: [[routing_key: :created, topic_or_queue: "orders.v2"]]]]
      )

    [publication] = config[:gateways][:kafka].publications
    assert publication.topic_or_queue == "orders.v2"
    assert publication.mapper == :json
    assert publication.transformers == []
  end

  test "merges subscriptions by name" do
    config =
      Config.merge(defaults(),
        gateways: [kafka: [subscriptions: [[name: :orders, batch_processing: :parallel]]]]
      )

    [subscription] = config[:gateways][:kafka].subscriptions
    assert subscription.batch_processing == :parallel
    assert subscription.routing_key == :created
  end

  test "keeps default entries not matched by an override" do
    defaults =
      put_in(defaults(), [:gateways, :kafka, :publications], [
        %{routing_key: :created, transformers: []},
        %{routing_key: :deleted, transformers: []}
      ])

    config =
      Config.merge(defaults,
        gateways: [kafka: [publications: [[routing_key: :created, topic_or_queue: "v2"]]]]
      )

    topics = config[:gateways][:kafka].publications
    created = Enum.find(topics, &(&1.routing_key == :created))
    assert created.topic_or_queue == "v2"
    assert created.transformers == []
    assert %{routing_key: :deleted, transformers: []} in topics
  end

  test "adds gateways present only in the overrides" do
    config =
      Config.merge(defaults(),
        gateways: [amqp: {AmqpAdapter, [connection: [host: "localhost"]]}]
      )

    assert config[:gateways][:amqp] == %{adapter: AmqpAdapter, connection: [host: "localhost"]}
    assert config[:gateways][:kafka].adapter == KafkaAdapter
  end

  test "normalizes gateway overrides given as maps" do
    config =
      Config.merge(defaults(),
        gateways: [kafka: %{publications: [%{routing_key: :created, persistent: true}]}]
      )

    [publication] = config[:gateways][:kafka].publications
    assert publication.persistent == true
    assert publication.mapper == :json
  end
end
