defmodule Ming.Gateway.KafkaTest do
  @moduledoc """
  Tests for `Ming.Gateway.Kafka`.

  Tests tagged `:kafka` are integration tests against a live broker.
  """

  use Ming.Gateway.Kafka.Case

  alias Ming.Gateway.Kafka
  alias Ming.Gateway.Kafka.Producer
  alias Ming.Message

  describe "init/1" do
    test "starts a brod client plus one subscriber per subscription" do
      name = unique_name(:kafka_gateway)
      sub1 = unique_name(:sub1)
      sub2 = unique_name(:sub2)

      opts = [
        name: name,
        command_processor: TestKafkaProcessor,
        connection: [endpoints: kafka_endpoints()],
        subscriptions: [
          [name: sub1, topic_or_queue: "topic1", routing_key: :rk1],
          [name: sub2, topic_or_queue: "topic2", routing_key: :rk2]
        ]
      ]

      assert {:ok, {_flags, children}} = Kafka.init(opts)
      assert length(children) == 3

      ids = Enum.map(children, & &1.id)
      assert Kafka.client_name(name) in ids
      assert sub1 in ids
      assert sub2 in ids
    end

    test "starts only the brod client when there are no subscriptions" do
      opts = [
        name: unique_name(:kafka_gateway),
        connection: [endpoints: kafka_endpoints()],
        publications: [[routing_key: :pub1, topic_or_queue: "topic1"]]
      ]

      assert {:ok, {_flags, children}} = Kafka.init(opts)
      assert length(children) == 1
    end

    test "raises when subscriptions are configured without a command_processor" do
      opts = [
        name: unique_name(:kafka_gateway),
        connection: [endpoints: kafka_endpoints()],
        subscriptions: [[name: :sub1, topic_or_queue: "topic1", routing_key: :rk1]]
      ]

      assert_raise ArgumentError, ~r/requires :command_processor/, fn ->
        Kafka.init(opts)
      end
    end

    test "raises when connection endpoints are missing" do
      opts = [name: unique_name(:kafka_gateway), connection: []]

      assert_raise KeyError, fn -> Kafka.init(opts) end
    end
  end

  describe "producer/0" do
    test "returns the producer module" do
      assert Kafka.producer() == Producer
    end
  end

  describe "provision_infrastructure/1" do
    test ":assume provision does not touch the broker" do
      opts = [
        connection: [endpoints: [{"unreachable", 1}]],
        publications: [[routing_key: :pub1, topic_or_queue: "topic1", provision: :assume]],
        subscriptions: [
          [name: :sub1, topic_or_queue: "topic2", routing_key: :rk1, provision: :assume]
        ]
      ]

      assert :ok = Kafka.provision_infrastructure(opts)
    end
  end

  describe "provision_infrastructure/1 against a live broker" do
    @tag :kafka
    test ":create creates the topic" do
      topic = unique_name("prov_topic_create")

      on_exit(fn -> :brod.delete_topics(kafka_endpoints(), [to_string(topic)], 10_000) end)

      opts = [
        connection: [endpoints: kafka_endpoints()],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: topic,
            routing_key: :rk,
            provision: {:create, num_partitions: 1, replication_factor: 1}
          ]
        ]
      ]

      assert :ok = Kafka.provision_infrastructure(opts)
      assert {:ok, _metadata} = :brod.get_metadata(kafka_endpoints(), [to_string(topic)])
    end

    @tag :kafka
    test ":validate fails for a missing topic" do
      opts = [
        connection: [endpoints: kafka_endpoints()],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: unique_name("prov_topic_missing"),
            routing_key: :rk,
            provision: :validate
          ]
        ]
      ]

      assert {:error, _} = Kafka.provision_infrastructure(opts)
    end

    @tag :kafka
    test ":validate succeeds for an existing topic" do
      topic = unique_name("prov_topic_validate")

      :ok =
        Kafka.provision_infrastructure(
          connection: [endpoints: kafka_endpoints()],
          subscriptions: [
            [
              name: unique_name(:sub),
              topic_or_queue: topic,
              routing_key: :rk,
              provision: {:create, num_partitions: 1, replication_factor: 1}
            ]
          ]
        )

      on_exit(fn -> :brod.delete_topics(kafka_endpoints(), [to_string(topic)], 10_000) end)

      opts = [
        connection: [endpoints: kafka_endpoints()],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: topic,
            routing_key: :rk,
            provision: :validate
          ]
        ]
      ]

      assert :ok = Kafka.provision_infrastructure(opts)
    end
  end

  describe "end-to-end" do
    @tag :kafka
    test "supervisor starts, publishes and consumes a message" do
      topic = unique_name("e2e_topic")
      routing_key = unique_name(:e2e_rk)
      name = unique_name(:e2e_gateway)

      Application.put_env(:ming, :kafka_test_target_pid, self())

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_test_target_pid)
        :brod.delete_topics(kafka_endpoints(), [to_string(topic)], 10_000)
      end)

      opts = [
        name: name,
        command_processor: TestKafkaProcessor,
        connection: [endpoints: kafka_endpoints()],
        publications: [[routing_key: routing_key, topic_or_queue: topic]],
        subscriptions: [
          [
            name: unique_name(:e2e_sub),
            topic_or_queue: topic,
            routing_key: routing_key,
            provision: {:create, num_partitions: 1, replication_factor: 1},
            consumer_config: [begin_offset: :earliest]
          ]
        ]
      ]

      assert :ok = Kafka.provision_infrastructure(opts)

      pid = start_supervised!({Kafka, opts})
      assert Process.alive?(pid)

      message = %Message{
        id: "e2e-1",
        payload: "end to end",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      gateway_config = [adapter: Kafka, name: name]
      publication = [routing_key: routing_key, topic_or_queue: topic]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)

      assert_receive {:consumed, %Message{payload: "end to end"} = consumed, _opts}, 10_000
      assert consumed.id == "e2e-1"
      assert consumed.routing_key == routing_key
    end
  end
end
