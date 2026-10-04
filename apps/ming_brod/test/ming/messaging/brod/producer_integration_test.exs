defmodule Ming.Messaging.Brod.ProducerIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :brod

  alias Ming.Context
  alias Ming.Messaging.Brod.Producer
  alias Ming.Messaging.Message

  @endpoints [{~c"localhost", 9092}]

  setup do
    client = :"brod_producer_test_#{System.unique_integer([:positive])}"
    topic = "ming-brod-producer-#{System.unique_integer([:positive])}"

    start_supervised!(%{id: client, start: {:brod, :start_link_client, [@endpoints, client, []]}})

    :ok =
      :brod.create_topics(
        @endpoints,
        [%{name: topic, num_partitions: 1, replication_factor: 1, assignments: [], configs: []}],
        %{timeout: 10_000}
      )

    %{client: client, topic: topic}
  end

  defp context(publication) do
    %Context{
      id: "ctx-1",
      correlation_id: "corr-1",
      request: %{},
      routing_key: publication[:routing_key],
      timeout: :infinity,
      timestamp: DateTime.utc_now(),
      metadata: %{ming_publication: publication}
    }
  end

  defp fetch_one(client, topic) do
    {:ok, {_high_wm_offset, [message | _]}} = :brod.fetch(client, topic, 0, 0)
    message
  end

  test "produce writes payload, key and CloudEvents headers to the topic", %{
    client: client,
    topic: topic
  } do
    publication = %{gateway_name: client, routing_key: topic, partition: 0}

    message = %Message{
      id: "msg-1",
      correlation_id: "corr-1",
      payload: "hello kafka",
      routing_key: topic,
      timestamp: ~U[2024-05-06 07:08:09.100Z],
      content_type: "application/json",
      type: "test.event",
      subject: "subject-1",
      partition_key: "key-1",
      source: "ming-brod-test",
      headers: %{"custom" => "header", retries: 3, retried: true}
    }

    assert :ok = Producer.produce(message, context(publication))

    {:kafka_message, _offset, key, value, _ts_type, ts, headers} = fetch_one(client, topic)
    headers = Map.new(headers)

    assert key == "key-1"
    assert value == "hello kafka"
    assert ts == DateTime.to_unix(~U[2024-05-06 07:08:09.100Z], :millisecond)

    assert headers["ce_id"] == "msg-1"
    assert headers["ce_correlationid"] == "corr-1"
    assert headers["ce_datacontenttype"] == "application/json"
    assert headers["ce_type"] == "test.event"
    assert headers["ce_subject"] == "subject-1"
    assert headers["ce_source"] == "ming-brod-test"
    assert headers["ce_time"] == "2024-05-06T07:08:09.100Z"
    assert headers["custom"] == "header"
    assert headers["retries"] == <<3::little-signed-64>>
    assert headers["retried"] == <<1>>
  end

  test "produce resolves the topic from the routing key by default", %{
    client: client,
    topic: topic
  } do
    publication = %{gateway_name: client, routing_key: topic, partition: 0}

    message = %Message{
      id: "msg-2",
      payload: "data",
      routing_key: topic,
      timestamp: DateTime.utc_now()
    }

    assert :ok = Producer.produce(message, context(publication))

    {:kafka_message, _offset, _key, "data", _ts_type, _ts, _headers} = fetch_one(client, topic)
  end

  test "produce with :async mode returns :ok", %{client: client, topic: topic} do
    publication = %{gateway_name: client, routing_key: topic, produce_mode: :async}

    message = %Message{
      id: "msg-3",
      payload: "async",
      routing_key: topic,
      timestamp: DateTime.utc_now()
    }

    assert :ok = Producer.produce(message, context(publication))
  end

  test "produce without a partition key uses :partition_on_nil_key", %{
    client: client,
    topic: topic
  } do
    publication = %{gateway_name: client, routing_key: topic, partition_on_nil_key: 0}

    message = %Message{
      id: "msg-4",
      payload: "no-key",
      routing_key: topic,
      timestamp: DateTime.utc_now()
    }

    assert :ok = Producer.produce(message, context(publication))

    {:kafka_message, _offset, key, "no-key", _ts_type, _ts, _headers} = fetch_one(client, topic)
    assert key == ""
  end
end
