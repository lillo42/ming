defmodule Ming.Gateway.KafkaExTest do
  @moduledoc """
  Tests for `Ming.Gateway.KafkaEx`.

  Tests tagged `:kafka_ex` are integration tests against a live broker.
  """

  use Ming.Gateway.KafkaEx.Case

  alias Elixir.KafkaEx.API, as: KafkaExAPI
  alias KafkaEx.Messages.Header
  alias Ming.Gateway.KafkaEx
  alias Ming.Gateway.KafkaEx.Producer
  alias Ming.Message

  defp fetch_records(client, topic, offset \\ 0) do
    {:ok, result} = KafkaExAPI.fetch(client, to_string(topic), 0, offset, max_wait_time: 5_000)

    result.records
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
    test "starts a kafka_ex client plus one consumer group per subscription" do
      name = unique_name(:kafka_ex_gateway)
      sub1 = unique_name(:sub1)
      sub2 = unique_name(:sub2)

      opts = [
        name: name,
        command_processor: TestKafkaExProcessor,
        connection: [endpoints: kafka_ex_endpoints()],
        subscriptions: [
          [name: sub1, topic_or_queue: "topic1", routing_key: :rk1],
          [name: sub2, topic_or_queue: "topic2", routing_key: :rk2]
        ]
      ]

      assert {:ok, {_flags, children}} = KafkaEx.init(opts)
      assert length(children) == 3

      ids = Enum.map(children, & &1.id)
      assert KafkaEx.client_name(name) in ids
      assert sub1 in ids
      assert sub2 in ids
    end

    test "starts one consumer group per performer when :number_of_performers is set" do
      name = unique_name(:kafka_ex_gateway)
      sub = unique_name(:sub)

      opts = [
        name: name,
        command_processor: TestKafkaExProcessor,
        connection: [endpoints: kafka_ex_endpoints()],
        subscriptions: [
          [name: sub, topic_or_queue: "topic1", routing_key: :rk1, number_of_performers: 3]
        ]
      ]

      assert {:ok, {_flags, children}} = KafkaEx.init(opts)
      assert length(children) == 4

      ids = Enum.map(children, & &1.id)
      assert KafkaEx.client_name(name) in ids
      assert {sub, 1} in ids
      assert {sub, 2} in ids
      assert {sub, 3} in ids
    end

    test "raises when :number_of_performers is not a positive integer" do
      opts = [
        name: unique_name(:kafka_ex_gateway),
        command_processor: TestKafkaExProcessor,
        connection: [endpoints: kafka_ex_endpoints()],
        subscriptions: [
          [name: :sub1, topic_or_queue: "topic1", routing_key: :rk1, number_of_performers: 0]
        ]
      ]

      assert_raise ArgumentError, ~r/:number_of_performers must be a positive integer/, fn ->
        KafkaEx.init(opts)
      end
    end

    test "starts only the kafka_ex client when there are no subscriptions" do
      opts = [
        name: unique_name(:kafka_ex_gateway),
        connection: [endpoints: kafka_ex_endpoints()],
        publications: [[routing_key: :pub1, topic_or_queue: "topic1"]]
      ]

      assert {:ok, {_flags, children}} = KafkaEx.init(opts)
      assert length(children) == 1
    end

    test "raises when subscriptions are configured without a command_processor" do
      opts = [
        name: unique_name(:kafka_ex_gateway),
        connection: [endpoints: kafka_ex_endpoints()],
        subscriptions: [[name: :sub1, topic_or_queue: "topic1", routing_key: :rk1]]
      ]

      assert_raise ArgumentError, ~r/requires :command_processor/, fn ->
        KafkaEx.init(opts)
      end
    end

    test "raises when connection endpoints are missing" do
      opts = [name: unique_name(:kafka_ex_gateway), connection: []]

      assert_raise KeyError, fn -> KafkaEx.init(opts) end
    end
  end

  describe "producer/0" do
    test "returns the producer module" do
      assert KafkaEx.producer() == Producer
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

      assert :ok = KafkaEx.provision_infrastructure(opts)
    end
  end

  describe "provision_infrastructure/1 against a live broker" do
    @tag :kafka_ex
    test ":create creates the topic" do
      topic = unique_name("prov_topic_create")

      client = start_provision_client!()
      on_exit(fn -> delete_topics([to_string(topic)]) end)

      opts = [
        connection: [endpoints: kafka_ex_endpoints()],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: topic,
            routing_key: :rk,
            provision: {:create, num_partitions: 1, replication_factor: 1}
          ]
        ]
      ]

      assert :ok = KafkaEx.provision_infrastructure(opts)
      assert {:ok, [_topic | _]} = KafkaExAPI.topics_metadata(client, [to_string(topic)])
    end

    @tag :kafka_ex
    test ":validate fails for a missing topic" do
      opts = [
        connection: [endpoints: kafka_ex_endpoints()],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: unique_name("prov_topic_missing"),
            routing_key: :rk,
            provision: :validate
          ]
        ]
      ]

      assert {:error, _} = KafkaEx.provision_infrastructure(opts)
    end

    @tag :kafka_ex
    test ":validate succeeds for an existing topic" do
      topic = unique_name("prov_topic_validate")

      :ok =
        KafkaEx.provision_infrastructure(
          connection: [endpoints: kafka_ex_endpoints()],
          subscriptions: [
            [
              name: unique_name(:sub),
              topic_or_queue: topic,
              routing_key: :rk,
              provision: {:create, num_partitions: 1, replication_factor: 1}
            ]
          ]
        )

      on_exit(fn -> delete_topics([to_string(topic)]) end)

      opts = [
        connection: [endpoints: kafka_ex_endpoints()],
        subscriptions: [
          [
            name: unique_name(:sub),
            topic_or_queue: topic,
            routing_key: :rk,
            provision: :validate
          ]
        ]
      ]

      assert :ok = KafkaEx.provision_infrastructure(opts)
    end
  end

  describe "end-to-end" do
    @tag :kafka_ex
    test "supervisor starts, publishes and consumes a message" do
      topic = unique_name("e2e_topic")
      routing_key = unique_name(:e2e_rk)
      name = unique_name(:e2e_gateway)

      Application.put_env(:ming, :kafka_ex_test_target_pid, self())

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_ex_test_target_pid)
        delete_topics([to_string(topic)])
      end)

      opts = [
        name: name,
        command_processor: TestKafkaExProcessor,
        connection: [endpoints: kafka_ex_endpoints()],
        publications: [[routing_key: routing_key, topic_or_queue: topic]],
        subscriptions: [
          [
            name: unique_name(:e2e_sub),
            topic_or_queue: topic,
            routing_key: routing_key,
            provision: {:create, num_partitions: 1, replication_factor: 1},
            consumer_config: [auto_offset_reset: :earliest]
          ]
        ]
      ]

      assert :ok = KafkaEx.provision_infrastructure(opts)

      pid = start_supervised!({KafkaEx, opts})
      assert Process.alive?(pid)

      message = %Message{
        id: "e2e-1",
        payload: "end to end",
        routing_key: routing_key,
        timestamp: DateTime.utc_now()
      }

      gateway_config = [adapter: KafkaEx, name: name]
      publication = [routing_key: routing_key, topic_or_queue: topic]

      assert :ok = Producer.publish(message, gateway: gateway_config, publication: publication)

      assert_receive {:consumed, %Message{payload: "end to end"} = consumed, _opts}, 15_000
      assert consumed.id == "e2e-1"
      assert consumed.routing_key == routing_key
    end

    @tag :kafka_ex
    test "post/2 round-trips through a real command processor" do
      topic = unique_name("e2e_cp_topic")
      gateway_name = unique_name(:e2e_cp_gateway)

      Application.put_env(:ming, :kafka_ex_e2e_pid, self())

      Application.put_env(:ming, KafkaExE2EProcessor,
        gateways: [
          [
            adapter: KafkaEx,
            name: gateway_name,
            connection: [endpoints: kafka_ex_endpoints()],
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
                consumer_config: [auto_offset_reset: :earliest],
                provision: {:create, num_partitions: 1, replication_factor: 1}
              ]
            ]
          ]
        ]
      )

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_ex_e2e_pid)
        Application.delete_env(:ming, KafkaExE2EProcessor)

        delete_topics([to_string(topic)])
      end)

      pid = start_supervised!(KafkaExE2EProcessor)
      assert Process.alive?(pid)

      assert :ok = KafkaExE2EProcessor.post(%{"id" => 1, "amount" => 42}, :e2e_order)

      assert_receive {:handled, :e2e_order, request, metadata, _assigns}, 15_000
      assert request == %{"id" => 1, "amount" => 42}
      assert metadata[:routing_key] == :e2e_order
    end

    @provision {:create, num_partitions: 1, replication_factor: 1}

    defp boot_e2e_processor(publications, subscriptions, topics) do
      gateway_name = unique_name(:e2e_cp_gateway)

      Application.put_env(:ming, :kafka_ex_e2e_pid, self())

      Application.put_env(:ming, KafkaExE2EProcessor,
        gateways: [
          [
            adapter: KafkaEx,
            name: gateway_name,
            connection: [endpoints: kafka_ex_endpoints()],
            publications: publications,
            subscriptions: subscriptions
          ]
        ]
      )

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_ex_e2e_pid)
        Application.delete_env(:ming, :kafka_ex_e2e_response)
        Application.delete_env(:ming, KafkaExE2EProcessor)
        delete_topics(topics)
      end)

      pid = start_supervised!(KafkaExE2EProcessor)
      assert Process.alive?(pid)

      gateway_name
    end

    defp e2e_subscription(name, topic, routing_key, extra \\ []) do
      [
        name: name,
        topic_or_queue: topic,
        routing_key: routing_key,
        group_id: to_string(name),
        consumer_config: [auto_offset_reset: :earliest],
        provision: @provision
      ] ++ extra
    end

    @tag :kafka_ex
    test "requeued messages without a requeue routing key are not redelivered" do
      topic = unique_name("e2e_rq_none_topic")

      Application.put_env(:ming, :kafka_ex_e2e_response, :requeue)

      boot_e2e_processor(
        [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
        [e2e_subscription(unique_name(:e2e_rq_none_sub), topic, :e2e_order)],
        [to_string(topic)]
      )

      assert :ok = KafkaExE2EProcessor.post(%{"id" => 1}, :e2e_order)

      assert_receive {:handled, :e2e_order, %{"id" => 1}, _metadata, _assigns}, 15_000
      refute_receive {:handled, :e2e_order, %{"id" => 1}, _metadata, _assigns}, 3_000
    end

    @tag :kafka_ex
    test "requeued messages are republished to the requeue topic" do
      topic = unique_name("e2e_rq_topic")
      retry_topic = unique_name("e2e_rq_retry")

      Application.put_env(:ming, :kafka_ex_e2e_response, :requeue)

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

      assert :ok = KafkaExE2EProcessor.post(%{"id" => 1}, :e2e_order)

      assert_receive {:handled, :e2e_order, %{"id" => 1}, _metadata, _assigns}, 15_000
      assert_receive {:handled, :e2e_retry, %{"id" => 1}, _metadata, _assigns}, 15_000
    end

    @tag :kafka_ex
    test "rejected messages are forwarded to the dead letter topic" do
      topic = unique_name("e2e_dlq_topic")
      dlq_topic = unique_name("e2e_dlq_dlq")

      Application.put_env(:ming, :kafka_ex_e2e_response, :reject)

      gateway_name =
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

      client = KafkaEx.client_name(gateway_name)

      assert :ok = KafkaExE2EProcessor.post(%{"id" => 2}, :e2e_order)

      assert_receive {:handled, :e2e_order, %{"id" => 2}, _metadata, _assigns}, 15_000

      assert eventually(fn -> fetch_records(client, dlq_topic) != [] end)

      [record] = fetch_records(client, dlq_topic)
      assert JSON.decode!(record.value) == %{"id" => 2}

      headers = Map.new(record.headers, &Header.to_tuple/1)
      assert headers["ORIGINAL_TOPIC"] == to_string(topic)
    end

    @tag :kafka_ex
    test "unacceptable messages are forwarded to the invalid message topic" do
      topic = unique_name("e2e_inv_topic")
      invalid_topic = unique_name("e2e_inv_invalid")

      gateway_name =
        boot_e2e_processor(
          [
            [routing_key: :e2e_order, topic_or_queue: topic, provision: @provision],
            [routing_key: :e2e_invalid, topic_or_queue: invalid_topic, provision: @provision]
          ],
          [
            e2e_subscription(unique_name(:e2e_inv_sub), topic, :e2e_order,
              invalid_message_routing_key: :e2e_invalid
            )
          ],
          [to_string(topic), to_string(invalid_topic)]
        )

      client = KafkaEx.client_name(gateway_name)

      assert {:ok, _metadata} =
               KafkaExAPI.produce(client, to_string(topic), 0, [%{value: "not json{{"}])

      assert eventually(fn -> fetch_records(client, invalid_topic) != [] end)

      [record] = fetch_records(client, invalid_topic)
      assert record.value == "not json{{"

      headers = Map.new(record.headers, &Header.to_tuple/1)
      assert headers["ORIGINAL_TOPIC"] == to_string(topic)
    end

    @tag :kafka_ex
    test "consumes records from foreign producers without CloudEvents headers" do
      topic = unique_name("e2e_foreign_topic")
      name = unique_name(:e2e_foreign_gateway)

      Application.put_env(:ming, :kafka_ex_test_target_pid, self())

      opts = [
        name: name,
        command_processor: TestKafkaExProcessor,
        connection: [endpoints: kafka_ex_endpoints()],
        publications: [[routing_key: :e2e_order, topic_or_queue: topic]],
        subscriptions: [
          [
            name: unique_name(:e2e_foreign_sub),
            topic_or_queue: topic,
            routing_key: :e2e_order,
            group_id: unique_name("e2e_foreign_group") |> to_string(),
            consumer_config: [auto_offset_reset: :earliest],
            provision: @provision
          ]
        ]
      ]

      on_exit(fn ->
        Application.delete_env(:ming, :kafka_ex_test_target_pid)
        delete_topics([to_string(topic)])
      end)

      assert :ok = KafkaEx.provision_infrastructure(opts)
      start_supervised!({KafkaEx, opts})

      client = KafkaEx.client_name(name)

      assert {:ok, _metadata} =
               KafkaExAPI.produce(client, to_string(topic), 0, [
                 %{key: "foreign-key", value: ~s({"id": 7})}
               ])

      assert_receive {:consumed, %Message{} = message, _opts}, 15_000
      assert message.payload == ~s({"id": 7})
      assert message.partition_key == "foreign-key"
      assert message.spec_version == "1.0"
      assert message.routing_key == :e2e_order
    end

    @tag :kafka_ex
    test "skips poison payloads without crashing the consumer" do
      topic = unique_name("e2e_poison_topic")

      gateway_name =
        boot_e2e_processor(
          [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
          [e2e_subscription(unique_name(:e2e_poison_sub), topic, :e2e_order)],
          [to_string(topic)]
        )

      client = KafkaEx.client_name(gateway_name)

      assert {:ok, _} = KafkaExAPI.produce(client, to_string(topic), 0, [%{value: "not json{{"}])
      assert {:ok, _} = KafkaExAPI.produce(client, to_string(topic), 0, [%{value: ~s({"id": 8})}])

      assert_receive {:handled, :e2e_order, %{"id" => 8}, _metadata, _assigns}, 15_000
    end

    @tag :kafka_ex
    test "propagates trace context through produce and consume" do
      topic = unique_name("e2e_trace_topic")

      gateway_name =
        boot_e2e_processor(
          [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
          [e2e_subscription(unique_name(:e2e_trace_sub), topic, :e2e_order)],
          [to_string(topic)]
        )

      trace_parent = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

      assert :ok =
               KafkaExE2EProcessor.post(%{"id" => 9},
                 routing_key: :e2e_order,
                 metadata: %{trace_parent: trace_parent}
               )

      client = KafkaEx.client_name(gateway_name)
      [record] = fetch_records(client, topic)
      headers = Map.new(record.headers, &Header.to_tuple/1)
      assert headers["ce_traceparent"] == trace_parent

      assert_receive {:handled, :e2e_order, %{"id" => 9}, _metadata, _assigns}, 15_000
    end

    @tag :kafka_ex
    test "concurrent posts all succeed" do
      topic = unique_name("e2e_conc_topic")

      boot_e2e_processor(
        [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
        [e2e_subscription(unique_name(:e2e_conc_sub), topic, :e2e_order)],
        [to_string(topic)]
      )

      results =
        1..20
        |> Task.async_stream(fn i -> KafkaExE2EProcessor.post(%{"i" => i}, :e2e_order) end,
          max_concurrency: 10
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &(&1 == :ok))
    end

    @tag :kafka_ex
    test "oversized payloads return an error instead of crashing" do
      topic = unique_name("e2e_big_topic")

      boot_e2e_processor(
        [[routing_key: :e2e_order, topic_or_queue: topic, provision: @provision]],
        [],
        [to_string(topic)]
      )

      big = String.duplicate("x", 2_000_000)

      assert {:error, _reason} = KafkaExE2EProcessor.post(%{"data" => big}, :e2e_order)
    end
  end

  defp start_provision_client! do
    start_supervised!(%{
      id: unique_name(:provision_client),
      start:
        {KafkaExAPI, :start_client,
         [[brokers: kafka_ex_endpoints(), consumer_group: :no_consumer_group]]}
    })
  end
end

defmodule KafkaExE2EHandler do
  @moduledoc false
  @behaviour Ming.Handler

  # Sends {:handled, routing_key, request, metadata, assigns} to the pid in
  # :kafka_ex_e2e_pid. The response for :e2e_order is read from
  # :kafka_ex_e2e_response (default :ok); other routing keys always return :ok.
  def handle(request, context) do
    send(
      Application.get_env(:ming, :kafka_ex_e2e_pid),
      {:handled, context.routing_key, request, context.metadata, context.assigns}
    )

    case context.routing_key do
      :e2e_order -> Application.get_env(:ming, :kafka_ex_e2e_response, :ok)
      _other -> :ok
    end
  end
end

defmodule KafkaExE2ERouter do
  @moduledoc false
  use Ming.Router

  register(:e2e_order, handler: KafkaExE2EHandler)
  register(:e2e_retry, handler: KafkaExE2EHandler)
  register(:e2e_dlq, handler: KafkaExE2EHandler)
end

defmodule KafkaExE2EProcessor do
  @moduledoc false
  use Ming.CommandProcessor, otp_app: :ming

  router(KafkaExE2ERouter)
end
