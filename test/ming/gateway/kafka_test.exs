defmodule Ming.Gateway.KafkaTest do
  @moduledoc """
  Tests for `Ming.Gateway.Kafka`.

  Tests tagged `:kafka` are integration tests against a live broker.
  """

  use Ming.Gateway.Kafka.Case

  require Record

  alias Ming.Gateway.Kafka
  alias Ming.Gateway.Kafka.Producer
  alias Ming.Message

  Record.defrecordp(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "kafka_protocol/include/kpro_public.hrl")
  )

  defp fetch_records(topic, offset \\ 0) do
    {:ok, {_high_watermark, records}} =
      :brod.fetch(kafka_endpoints(), to_string(topic), 0, offset, %{max_wait_time: 5_000})

    records
  end

  defp eventually(fun, attempts \\ 50)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(200)
      eventually(fun, attempts - 1)
    end
  end

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

    @tag :kafka
    test "post/2 round-trips through a real command processor" do
      topic = unique_name("e2e_cp_topic")

      Application.put_env(:ming, :kafka_e2e_pid, self())

      Application.put_env(:ming, KafkaE2EProcessor,
        gateways: [
          [
            adapter: Kafka,
            name: unique_name(:e2e_cp_gateway),
            connection: [endpoints: kafka_endpoints()],
            publications: [
              [
                routing_key: :e2e_order,
                topic_or_queue: topic,
                provision: {:create, num_partitions: 1, replication_factor: 1}
              ]
            ],
            subscriptions: [
              [
                name: unique_name(:e2e_cp_sub),
                topic_or_queue: topic,
                routing_key: :e2e_order,
                group_id: unique_name("e2e_cp_group") |> to_string(),
                consumer_config: [begin_offset: :earliest],
                provision: {:create, num_partitions: 1, replication_factor: 1}
              ]
            ]
          ]
        ]
      )

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_e2e_pid)
        Application.delete_env(:ming, KafkaE2EProcessor)
        :brod.delete_topics(kafka_endpoints(), [to_string(topic)], 10_000)
      end)

      pid = start_supervised!(KafkaE2EProcessor)
      assert Process.alive?(pid)

      assert :ok = KafkaE2EProcessor.post(%{"id" => 1, "amount" => 42}, :e2e_order)

      assert_receive {:handled, :e2e_order, request, metadata, _assigns}, 15_000
      assert request == %{"id" => 1, "amount" => 42}
      assert metadata[:routing_key] == :e2e_order
    end

    @provision {:create, num_partitions: 1, replication_factor: 1}

    defp boot_e2e_processor(publications, subscriptions, topics) do
      gateway_name = unique_name(:e2e_cp_gateway)

      Application.put_env(:ming, :kafka_e2e_pid, self())

      Application.put_env(:ming, KafkaE2EProcessor,
        gateways: [
          [
            adapter: Kafka,
            name: gateway_name,
            connection: [endpoints: kafka_endpoints()],
            publications: publications,
            subscriptions: subscriptions
          ]
        ]
      )

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_e2e_pid)
        Application.delete_env(:ming, :kafka_e2e_response)
        Application.delete_env(:ming, KafkaE2EProcessor)
        :brod.delete_topics(kafka_endpoints(), topics, 10_000)
      end)

      pid = start_supervised!(KafkaE2EProcessor)
      assert Process.alive?(pid)

      gateway_name
    end

    defp e2e_subscription(name, topic, routing_key, extra \\ []) do
      [
        name: name,
        topic_or_queue: topic,
        routing_key: routing_key,
        group_id: to_string(name),
        consumer_config: [begin_offset: :earliest],
        provision: @provision
      ] ++ extra
    end

    @tag :kafka
    test "requeued messages without a requeue routing key are not redelivered" do
      topic = unique_name("e2e_rq_none_topic")

      Application.put_env(:ming, :kafka_e2e_response, :requeue)

      boot_e2e_processor(
        [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
        [e2e_subscription(unique_name(:e2e_rq_none_sub), topic, :e2e_order)],
        [to_string(topic)]
      )

      assert :ok = KafkaE2EProcessor.post(%{"id" => 1}, :e2e_order)

      assert_receive {:handled, :e2e_order, %{"id" => 1}, _metadata, _assigns}, 15_000
      refute_receive {:handled, :e2e_order, %{"id" => 1}, _metadata, _assigns}, 3_000
    end

    @tag :kafka
    test "requeued messages are republished to the requeue topic" do
      topic = unique_name("e2e_rq_topic")
      retry_topic = unique_name("e2e_rq_retry")

      Application.put_env(:ming, :kafka_e2e_response, :requeue)

      boot_e2e_processor(
        [
          [routing_key: :e2e_order, topic_or_queue: topic, provision: @provision],
          [routing_key: :e2e_retry, topic_or_queue: retry_topic, provision: @provision]
        ],
        [
          e2e_subscription(unique_name(:e2e_rq_sub), topic, :e2e_order,
            requeue_routing_key: :e2e_retry
          ),
          e2e_subscription(unique_name(:e2e_rq_retry_sub), retry_topic, :e2e_retry)
        ],
        [to_string(topic), to_string(retry_topic)]
      )

      assert :ok = KafkaE2EProcessor.post(%{"id" => 1}, :e2e_order)

      assert_receive {:handled, :e2e_order, %{"id" => 1}, _metadata, _assigns}, 15_000
      assert_receive {:handled, :e2e_retry, %{"id" => 1}, _metadata, _assigns}, 15_000
    end

    @tag :kafka
    test "rejected messages are forwarded to the dead letter topic" do
      topic = unique_name("e2e_dlq_topic")
      dlq_topic = unique_name("e2e_dlq_dlq")

      Application.put_env(:ming, :kafka_e2e_response, :reject)

      boot_e2e_processor(
        [
          [routing_key: :e2e_order, topic_or_queue: topic, provision: @provision],
          [routing_key: :e2e_dlq, topic_or_queue: dlq_topic, provision: @provision]
        ],
        [
          e2e_subscription(unique_name(:e2e_dlq_sub), topic, :e2e_order,
            dead_letter_queue_routing_key: :e2e_dlq
          )
        ],
        [to_string(topic), to_string(dlq_topic)]
      )

      assert :ok = KafkaE2EProcessor.post(%{"id" => 2}, :e2e_order)

      assert_receive {:handled, :e2e_order, %{"id" => 2}, _metadata, _assigns}, 15_000

      assert eventually(fn -> fetch_records(dlq_topic) != [] end)

      [record] = fetch_records(dlq_topic)
      assert JSON.decode!(kafka_message(record, :value)) == %{"id" => 2}

      headers = record |> kafka_message(:headers) |> Map.new()
      assert headers["ORIGINAL_TOPIC"] == to_string(topic)
    end

    @tag :kafka
    test "consumes records from foreign producers without CloudEvents headers" do
      topic = unique_name("e2e_foreign_topic")
      name = unique_name(:e2e_foreign_gateway)

      Application.put_env(:ming, :kafka_test_target_pid, self())

      opts = [
        name: name,
        command_processor: TestKafkaProcessor,
        connection: [endpoints: kafka_endpoints()],
        publications: [[routing_key: :e2e_order, topic_or_queue: topic]],
        subscriptions: [
          [
            name: unique_name(:e2e_foreign_sub),
            topic_or_queue: topic,
            routing_key: :e2e_order,
            group_id: unique_name("e2e_foreign_group") |> to_string(),
            consumer_config: [begin_offset: :earliest],
            provision: @provision
          ]
        ]
      ]

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_test_target_pid)
        :brod.delete_topics(kafka_endpoints(), [to_string(topic)], 10_000)
      end)

      assert :ok = Kafka.provision_infrastructure(opts)
      start_supervised!({Kafka, opts})

      client = Kafka.client_name(name)

      assert :ok =
               :brod.produce_sync(client, to_string(topic), :random, "foreign-key", ~s({"id": 7}))

      assert_receive {:consumed, %Message{} = message, _opts}, 15_000
      assert message.payload == ~s({"id": 7})
      assert message.partition_key == "foreign-key"
      assert message.spec_version == "1.0"
      assert message.routing_key == :e2e_order
    end

    @tag :kafka
    test "skips poison payloads without crashing the consumer" do
      topic = unique_name("e2e_poison_topic")

      gateway_name =
        boot_e2e_processor(
          [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
          [e2e_subscription(unique_name(:e2e_poison_sub), topic, :e2e_order)],
          [to_string(topic)]
        )

      client = Kafka.client_name(gateway_name)

      assert :ok = :brod.produce_sync(client, to_string(topic), :random, <<>>, "not json{{")
      assert :ok = :brod.produce_sync(client, to_string(topic), :random, <<>>, ~s({"id": 8}))

      assert_receive {:handled, :e2e_order, %{"id" => 8}, _metadata, _assigns}, 15_000
    end

    @tag :kafka
    test "propagates trace context through produce and consume" do
      topic = unique_name("e2e_trace_topic")

      boot_e2e_processor(
        [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
        [e2e_subscription(unique_name(:e2e_trace_sub), topic, :e2e_order)],
        [to_string(topic)]
      )

      trace_parent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      assert :ok =
               KafkaE2EProcessor.post(%{"id" => 9},
                 routing_key: :e2e_order,
                 metadata: %{trace_parent: trace_parent}
               )

      [record] = fetch_records(topic)
      headers = record |> kafka_message(:headers) |> Map.new()
      assert headers["ce_traceparent"] == trace_parent

      assert_receive {:handled, :e2e_order, %{"id" => 9}, _metadata, _assigns}, 15_000
    end

    @tag :kafka
    test "concurrent posts all succeed" do
      topic = unique_name("e2e_conc_topic")

      boot_e2e_processor(
        [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
        [e2e_subscription(unique_name(:e2e_conc_sub), topic, :e2e_order)],
        [to_string(topic)]
      )

      results =
        1..20
        |> Task.async_stream(fn i -> KafkaE2EProcessor.post(%{"i" => i}, :e2e_order) end,
          max_concurrency: 10
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &(&1 == :ok))
    end

    @tag :kafka
    test "oversized payloads return an error instead of crashing" do
      topic = unique_name("e2e_big_topic")

      boot_e2e_processor(
        [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
        [],
        [to_string(topic)]
      )

      big = String.duplicate("x", 2_000_000)

      assert {:error, _reason} = KafkaE2EProcessor.post(%{"data" => big}, :e2e_order)
    end
  end
end

defmodule KafkaE2EHandler do
  @moduledoc false
  @behaviour Ming.Handler

  # Sends {:handled, routing_key, request, metadata, assigns} to the pid in
  # :kafka_e2e_pid. The response for :e2e_order is read from
  # :kafka_e2e_response (default :ok); other routing keys always return :ok.
  def handle(request, context) do
    send(
      Application.get_env(:ming, :kafka_e2e_pid),
      {:handled, context.routing_key, request, context.metadata, context.assigns}
    )

    case context.routing_key do
      :e2e_order -> Application.get_env(:ming, :kafka_e2e_response, :ok)
      _other -> :ok
    end
  end
end

defmodule KafkaE2ERouter do
  @moduledoc false
  use Ming.Router

  register(:e2e_order, handler: KafkaE2EHandler)
  register(:e2e_retry, handler: KafkaE2EHandler)
  register(:e2e_dlq, handler: KafkaE2EHandler)
end

defmodule KafkaE2EProcessor do
  @moduledoc false
  use Ming.CommandProcessor, otp_app: :ming

  router(KafkaE2ERouter)
end
