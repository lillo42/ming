defmodule Ming.Messaging.Brod.GatewayIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :brod

  alias Ming.Context
  alias Ming.Messaging.Brod.Consumer
  alias Ming.Messaging.Brod.Gateway
  alias Ming.Messaging.Brod.Producer
  alias Ming.Messaging.Message

  @endpoints [{~c"localhost", 9092}]

  defp unique_name(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp gateway_name, do: :"brod_integration_#{System.unique_integer([:positive])}"

  defp start_gateway!(config) do
    name = Map.fetch!(config, :name)
    start_supervised!(%{id: name, start: {Gateway, :start_link, [config]}})
  end

  defp topic_exists?(topic) do
    {:ok, metadata} = :brod.get_metadata(@endpoints, [topic])

    Enum.any?(metadata.topics, fn topic_metadata ->
      topic_metadata.name == topic and topic_metadata.error_code == :no_error
    end)
  end

  test "creates the topics of :create entries on startup" do
    topic = unique_name("ming-brod-gw-create")

    start_gateway!(%{
      name: gateway_name(),
      endpoints: @endpoints,
      publications: [%{routing_key: topic}]
    })

    assert topic_exists?(topic)
  end

  test "does not create topics of :assume entries" do
    topic = unique_name("ming-brod-gw-assume")

    start_gateway!(%{
      name: gateway_name(),
      endpoints: @endpoints,
      publications: [%{routing_key: topic, provisioner: :assume}]
    })

    refute topic_exists?(topic)
  end

  test "fails to start when a :validate entry has a missing topic" do
    topic = unique_name("ming-brod-gw-validate")

    assert {:error, {:topic_not_found, ^topic}} =
             Gateway.start_link(%{
               name: gateway_name(),
               endpoints: @endpoints,
               publications: [%{routing_key: topic, provisioner: :validate}]
             })
  end

  test "starts when a :validate entry is covered by a :create entry" do
    topic = unique_name("ming-brod-gw-validate-created")

    start_gateway!(%{
      name: gateway_name(),
      endpoints: @endpoints,
      publications: [%{routing_key: topic}],
      subscriptions: [
        %{
          name: :sub,
          routing_key: topic,
          group_id: unique_name("ming-brod-group"),
          provisioner: :validate
        }
      ]
    })

    assert topic_exists?(topic)
  end

  test "publishes and consumes a message end-to-end" do
    topic = unique_name("ming-brod-e2e")
    gateway = gateway_name()

    start_gateway!(%{
      name: gateway,
      endpoints: @endpoints,
      publications: [%{routing_key: topic}],
      subscriptions: [
        %{
          name: :sub,
          routing_key: topic,
          group_id: unique_name("ming-brod-group"),
          consumer_config: [begin_offset: :earliest]
        }
      ]
    })

    publication = %{gateway_name: gateway, routing_key: topic}

    context = %Context{
      id: "ctx-1",
      correlation_id: "corr-1",
      request: %{},
      routing_key: topic,
      timeout: :infinity,
      timestamp: DateTime.utc_now(),
      metadata: %{ming_publication: publication}
    }

    outbound = %Message{
      id: "msg-e2e-1",
      correlation_id: "corr-1",
      payload: "hello kafka",
      routing_key: topic,
      timestamp: DateTime.utc_now(),
      content_type: "application/json",
      type: "test.event",
      subject: "subject-1",
      partition_key: "key-1",
      source: "ming-brod-test",
      headers: %{"custom" => "header"}
    }

    assert :ok = Producer.produce(outbound, context)

    subscription = %{
      gateway_name: gateway,
      name: :sub,
      routing_key: topic,
      receive_timeout: 15_000
    }

    assert [inbound] = Consumer.receive_messages(subscription)

    assert inbound.id == "msg-e2e-1"
    assert inbound.correlation_id == "corr-1"
    assert inbound.payload == "hello kafka"
    assert inbound.routing_key == topic
    assert inbound.content_type == "application/json"
    assert inbound.type == "test.event"
    assert inbound.subject == "subject-1"
    assert inbound.partition_key == "key-1"
    assert inbound.source == "ming-brod-test"
    assert inbound.headers["custom"] == "header"
    assert %{topic: ^topic, offset: offset} = inbound.headers[:ming_brod]
    assert is_integer(offset)

    assert :ok = Consumer.ack(subscription, inbound)
  end
end
