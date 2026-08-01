defmodule Ming.Gateway.KafkaEx.ConsumerTest do
  @moduledoc """
  Unit tests for `Ming.Gateway.KafkaEx.Consumer` (no broker required).
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias KafkaEx.Messages.Fetch.Record
  alias KafkaEx.Messages.Header
  alias Ming.Gateway.KafkaEx.Consumer
  alias Ming.Message

  defp kafka_record(opts \\ []) do
    Record.build(
      offset: Keyword.get(opts, :offset, 0),
      key: Keyword.get(opts, :key),
      value: Keyword.get(opts, :value, "payload"),
      timestamp: Keyword.get(opts, :timestamp, 1_700_000_000_000),
      headers: Keyword.get(opts, :headers, [])
    )
  end

  defp state(opts \\ []) do
    %{
      topic: "orders",
      partition: 0,
      routing_key: :order_created,
      command_processor: TestKafkaExProcessor,
      timeout: :infinity,
      requeue_routing_key: nil,
      requeue_count: nil,
      dead_letter_queue_routing_key: nil,
      invalid_message_routing_key: nil
    }
    |> Map.merge(Map.new(opts))
  end

  setup do
    Application.put_env(:ming, :kafka_ex_test_target_pid, self())

    on_exit(fn ->
      Application.delete_env(:ming, :kafka_ex_test_target_pid)
      Application.delete_env(:ming, :kafka_ex_test_response)
    end)

    :ok
  end

  describe "init/3" do
    test "builds state from topic, partition and extra args" do
      extra_args = [routing_key: :order_created, command_processor: TestKafkaExProcessor]

      assert {:ok, state} = Consumer.init("orders", 3, Map.new(extra_args))
      assert state.topic == "orders"
      assert state.partition == 3
      assert state.routing_key == :order_created
      assert state.command_processor == TestKafkaExProcessor
      assert state.timeout == :infinity
    end

    test "raises when routing_key is missing" do
      extra_args =
        %{routing_key: :order_created, command_processor: TestKafkaExProcessor}
        |> Map.delete(:routing_key)

      assert_raise KeyError, fn ->
        Consumer.init("orders", 0, extra_args)
      end
    end
  end

  describe "to_message/2" do
    test "converts a kafka record with CloudEvents headers" do
      record =
        kafka_record(
          offset: 42,
          key: "order-1",
          value: "order payload",
          headers: [
            Header.new("ce_id", "msg-1"),
            Header.new("ce_type", "com.example.order"),
            Header.new("ce_source", "https://example.com/orders"),
            Header.new("ce_subject", "order-1"),
            Header.new("ce_specversion", "1.0"),
            Header.new("ce_datacontenttype", "application/json"),
            Header.new("ce_correlationid", "corr-1"),
            Header.new("ce_time", "2024-01-15T10:30:00Z")
          ]
        )

      message = Consumer.to_message(record, state())

      assert %Message{} = message
      assert message.id == "msg-1"
      assert message.type == "com.example.order"
      assert message.source == URI.new!("https://example.com/orders")
      assert message.subject == "order-1"
      assert message.spec_version == "1.0"
      assert message.content_type == "application/json"
      assert message.correlation_id == "corr-1"
      assert message.payload == "order payload"
      assert message.partition_key == "order-1"
      assert message.routing_key == :order_created
      assert message.timestamp == ~U[2024-01-15 10:30:00Z]

      assert message.headers[:kafka_offset] == 42
      assert message.headers[:kafka_partition] == 0
      assert message.headers[:kafka_topic] == "orders"
    end

    test "generates an id when ce_id is missing" do
      message = Consumer.to_message(kafka_record(), state())

      assert is_binary(message.id)
      assert message.id != ""
    end

    test "uses the kafka record timestamp when ce_time is missing" do
      ts = 1_700_000_000_000
      message = Consumer.to_message(kafka_record(timestamp: ts), state())

      assert message.timestamp == DateTime.from_unix!(ts, :millisecond)
    end

    test "applies defaults for missing CloudEvents headers" do
      message = Consumer.to_message(kafka_record(), state())

      assert message.spec_version == "1.0"
      assert message.content_type == "text/plain"
      assert message.source == URI.new!("https://hex.pm/packages/ming")
      assert message.type == nil
      assert message.correlation_id == nil
    end

    test "handles records without headers" do
      message = Consumer.to_message(kafka_record(headers: nil), state())

      assert %Message{} = message
      assert message.payload == "payload"
    end
  end

  describe "handle_message_set/2" do
    test "dispatches to the command processor and commits the batch" do
      record = kafka_record(value: "hello", headers: [Header.new("ce_id", "msg-ack")])

      assert {:async_commit, state} = Consumer.handle_message_set([record], state())

      assert_receive {:consumed, %Message{payload: "hello", id: "msg-ack"}, opts}
      assert opts[:routing_key] == :ming_consume_message

      assert opts[:metadata] == %{
               routing_key: :order_created,
               command_process: TestKafkaExProcessor
             }

      assert state.routing_key == :order_created
    end

    test "dispatches every record in the batch" do
      records = [kafka_record(value: "one"), kafka_record(value: "two")]

      assert {:async_commit, _state} = Consumer.handle_message_set(records, state())

      assert_receive {:consumed, %Message{payload: "one"}, _opts}
      assert_receive {:consumed, %Message{payload: "two"}, _opts}
    end

    test "commits when the processor rejects the message" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, :reject})

      assert {:async_commit, _state} = Consumer.handle_message_set([kafka_record()], state())
      assert_receive {:consumed, %Message{}, _opts}
    end

    test "commits and logs an error when the processor requeues the message" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, :requeue})

      log =
        capture_log([level: :error], fn ->
          assert {:async_commit, _state} = Consumer.handle_message_set([kafka_record()], state())
        end)

      assert log =~ "Kafka does not support requeue"
      assert log =~ "acked"
      assert_receive {:consumed, %Message{}, _opts}
    end

    test "republishes requeued messages to the requeue routing key and commits" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, :requeue})

      assert {:async_commit, _state} =
               Consumer.handle_message_set(
                 [kafka_record()],
                 state(requeue_routing_key: :orders_retry)
               )

      assert_receive {:consumed, %Message{}, _opts}
      assert_receive {:posted, %Message{payload: "payload"}, :orders_retry}
    end

    test "requeues with an incremented requeue counter header" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, :requeue})

      assert {:async_commit, _state} =
               Consumer.handle_message_set(
                 [kafka_record()],
                 state(requeue_routing_key: :orders_retry, requeue_count: 3)
               )

      assert_receive {:posted, %Message{} = message, :orders_retry}
      assert message.headers["x-ming-requeue-count"] == 1
    end

    test "forwards to the dead letter queue when the requeue count is reached" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, :requeue})

      record = kafka_record(headers: [Header.new("x-ming-requeue-count", "3")])

      assert {:async_commit, _state} =
               Consumer.handle_message_set(
                 [record],
                 state(
                   requeue_routing_key: :orders_retry,
                   requeue_count: 3,
                   dead_letter_queue_routing_key: :orders_dlq
                 )
               )

      assert_receive {:posted, %Message{}, :orders_dlq}
      refute_receive {:posted, _, :orders_retry}
    end

    test "forwards rejected messages to the dead letter queue and commits" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, :reject})

      assert {:async_commit, _state} =
               Consumer.handle_message_set(
                 [kafka_record()],
                 state(dead_letter_queue_routing_key: :orders_dlq)
               )

      assert_receive {:consumed, %Message{}, _opts}

      assert_receive {:posted, %Message{} = dlq_message, :orders_dlq}
      assert dlq_message.headers["ORIGINAL_TOPIC"] == "orders"
      assert %DateTime{} = dlq_message.headers["ORIGINAL_TIMESTAMP"]
      assert Map.has_key?(dlq_message.headers, "ORIGINAL_TYPE")
    end

    test "commits rejected messages without a dead letter queue" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, :reject})

      log =
        capture_log([level: :error], fn ->
          assert {:async_commit, _state} = Consumer.handle_message_set([kafka_record()], state())
        end)

      assert log =~ "rejected message and no dead letter queue configured"
      assert_receive {:consumed, %Message{}, _opts}
      refute_receive {:posted, _, _}
    end

    test "forwards unaccepted messages to the invalid message routing key and commits" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, {:reject, :unaccepted}})

      assert {:async_commit, _state} =
               Consumer.handle_message_set(
                 [kafka_record()],
                 state(invalid_message_routing_key: :orders_invalid)
               )

      assert_receive {:consumed, %Message{}, _opts}

      assert_receive {:posted, %Message{} = invalid_message, :orders_invalid}
      assert invalid_message.headers["ORIGINAL_TOPIC"] == "orders"
    end

    test "handles unaccepted messages returned bare by a halted pipeline" do
      Application.put_env(:ming, :kafka_ex_test_response, {:reject, :unaccepted})

      assert {:async_commit, _state} =
               Consumer.handle_message_set(
                 [kafka_record()],
                 state(invalid_message_routing_key: :orders_invalid)
               )

      assert_receive {:consumed, %Message{}, _opts}
      assert_receive {:posted, %Message{}, :orders_invalid}
    end

    test "falls back to the dead letter queue for unaccepted messages" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, {:reject, :unaccepted}})

      assert {:async_commit, _state} =
               Consumer.handle_message_set(
                 [kafka_record()],
                 state(dead_letter_queue_routing_key: :orders_dlq)
               )

      assert_receive {:consumed, %Message{}, _opts}
      assert_receive {:posted, %Message{}, :orders_dlq}
    end

    test "commits and logs an error for unaccepted messages with no channel configured" do
      Application.put_env(:ming, :kafka_ex_test_response, {:ok, {:reject, :unaccepted}})

      log =
        capture_log([level: :error], fn ->
          assert {:async_commit, _state} = Consumer.handle_message_set([kafka_record()], state())
        end)

      assert log =~ "unacceptable"
      assert_receive {:consumed, %Message{}, _opts}
      refute_receive {:posted, _, _}
    end

    test "commits when the processor fails" do
      Application.put_env(:ming, :kafka_ex_test_response, {:error, :boom})

      assert {:async_commit, _state} = Consumer.handle_message_set([kafka_record()], state())
      assert_receive {:consumed, %Message{}, _opts}
    end
  end
end
