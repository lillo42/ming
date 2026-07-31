defmodule Ming.Gateway.KafkaEx.ProducerTest do
  @moduledoc """
  Integration tests for `Ming.Gateway.KafkaEx.Producer` against a live broker.
  """

  use Ming.Gateway.KafkaEx.Case

  alias Elixir.KafkaEx.API, as: KafkaExAPI
  alias KafkaEx.Messages.Header
  alias Ming.Gateway.KafkaEx
  alias Ming.Gateway.KafkaEx.Producer
  alias Ming.Message

  @moduletag :kafka_ex

  setup do
    topic = unique_name("producer_topic")
    gateway_name = unique_name(:producer_gateway)
    client = KafkaEx.client_name(gateway_name)

    :ok =
      KafkaEx.provision_infrastructure(
        connection: [endpoints: kafka_ex_endpoints()],
        publications: [
          [
            routing_key: :rk,
            topic_or_queue: topic,
            provision: {:create, num_partitions: 1, replication_factor: 1}
          ]
        ]
      )

    start_supervised!(%{
      id: :producer_client,
      start:
        {KafkaExAPI, :start_client,
         [
           [
             name: client,
             brokers: kafka_ex_endpoints(),
             consumer_group: :no_consumer_group
           ]
         ]}
    })

    on_exit(fn -> delete_topics([to_string(topic)]) end)

    [
      topic: to_string(topic),
      client: client,
      gateway_config: [adapter: KafkaEx, name: gateway_name],
      publication: [routing_key: :rk, topic_or_queue: topic]
    ]
  end

  defp fetch_records(client, topic, offset \\ 0) do
    {:ok, result} = KafkaExAPI.fetch(client, topic, 0, offset, max_wait_time: 5_000)

    result.records
  end

  describe "publish/2" do
    test "publishes a single message with CloudEvents headers", %{
      topic: topic,
      client: client,
      gateway_config: gateway_config,
      publication: publication
    } do
      message = %Message{
        id: "msg-1",
        payload: "hello kafka",
        routing_key: :rk,
        timestamp: ~U[2024-01-01T12:00:00Z],
        type: "com.example.event",
        source: "https://example.com/source",
        correlation_id: "corr-1"
      }

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)

      [record] = fetch_records(client, topic)

      assert record.value == "hello kafka"

      headers = Map.new(record.headers, &Header.to_tuple/1)
      assert headers["ce_id"] == "msg-1"
      assert headers["ce_type"] == "com.example.event"
      assert headers["ce_source"] == "https://example.com/source"
      assert headers["ce_correlationid"] == "corr-1"
      assert headers["ce_specversion"] == "1.0"
      assert headers["ce_time"] == "2024-01-01T12:00:00Z"
    end

    test "publishes iodata payloads", %{
      topic: topic,
      client: client,
      gateway_config: gateway_config,
      publication: publication
    } do
      # The default JSON mapper produces iodata, not a binary
      message = %Message{
        id: "iodata-msg",
        payload: ["hello ", ["io", "data"]],
        routing_key: :rk,
        timestamp: DateTime.utc_now()
      }

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)

      [record] = fetch_records(client, topic)
      assert record.value == "hello iodata"
    end

    test "publishes a list of messages", %{
      topic: topic,
      client: client,
      gateway_config: gateway_config,
      publication: publication
    } do
      messages =
        for i <- 1..3 do
          %Message{
            id: "msg-#{i}",
            payload: "payload-#{i}",
            routing_key: :rk,
            timestamp: DateTime.utc_now()
          }
        end

      assert [_, _, _] =
               Producer.publish(messages, gateway: gateway_config, publication: publication)

      records = fetch_records(client, topic)

      assert Enum.map(records, & &1.value) == [
               "payload-1",
               "payload-2",
               "payload-3"
             ]
    end

    test "uses the partition key as the kafka record key", %{
      topic: topic,
      client: client,
      gateway_config: gateway_config,
      publication: publication
    } do
      message = %Message{
        id: "keyed-msg",
        payload: "keyed",
        partition_key: "order-1",
        routing_key: :rk,
        timestamp: DateTime.utc_now()
      }

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)

      [record] = fetch_records(client, topic)
      assert record.key == "order-1"
    end

    test "preserves non-ASCII custom header values", %{
      topic: topic,
      client: client,
      gateway_config: gateway_config,
      publication: publication
    } do
      message = %Message{
        id: "utf8-msg",
        payload: "utf8",
        headers: %{"x-custom" => "café résumé"},
        routing_key: :rk,
        timestamp: DateTime.utc_now()
      }

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)

      [record] = fetch_records(client, topic)
      headers = Map.new(record.headers, &Header.to_tuple/1)
      assert headers["x-custom"] == "café résumé"
    end
  end
end
