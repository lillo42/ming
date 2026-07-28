defmodule Ming.Gateway.Kafka.ConsumerTest do
  @moduledoc """
  Unit tests for `Ming.Gateway.Kafka.Consumer` (no broker required).
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ming.Gateway.Kafka.Consumer
  alias Ming.Message

  # brod kafka_message record: {kafka_message, offset, key, value, ts_type, ts, headers}
  defp kafka_message(opts \\ []) do
    {:kafka_message, Keyword.get(opts, :offset, 0), Keyword.get(opts, :key, <<>>),
     Keyword.get(opts, :value, "payload"), :create, Keyword.get(opts, :ts, 1_700_000_000_000),
     Keyword.get(opts, :headers, [])}
  end

  defp state(opts \\ []) do
    %{
      topic: "orders",
      partition: 0,
      routing_key: :order_created,
      command_processor: TestKafkaProcessor,
      timeout: :infinity,
      requeue_routing_key: nil,
      dead_letter_queue_routing_key: nil,
      invalid_message_routing_key: nil
    }
    |> Map.merge(Map.new(opts))
  end

  setup do
    Application.put_env(:ming, :kafka_test_target_pid, self())

    on_exit(fn ->
      Application.delete_env(:ming, :kafka_test_target_pid)
      Application.delete_env(:ming, :kafka_test_response)
    end)

    :ok
  end

  describe "init/2" do
    test "builds state from init_info and cb_config" do
      init_info = %{
        group_id: "group",
        topic: "orders",
        partition: 3,
        commit_fun: fn _offset -> :ok end,
        ack_fun: fn _offset -> :ok end
      }

      cb_config = [routing_key: :order_created, command_processor: TestKafkaProcessor]

      assert {:ok, state} = Consumer.init(init_info, cb_config)
      assert state.topic == "orders"
      assert state.partition == 3
      assert state.routing_key == :order_created
      assert state.command_processor == TestKafkaProcessor
      assert state.timeout == :infinity
    end

    test "raises when routing_key is missing" do
      init_info = %{topic: "orders", partition: 0}

      assert_raise KeyError, fn ->
        Consumer.init(init_info, command_processor: TestKafkaProcessor)
      end
    end
  end

  describe "to_message/2" do
    test "converts a kafka record with CloudEvents headers" do
      record =
        kafka_message(
          offset: 42,
          key: "order-1",
          value: "order payload",
          headers: [
            {"ce_id", "msg-1"},
            {"ce_type", "com.example.order"},
            {"ce_source", "https://example.com/orders"},
            {"ce_subject", "order-1"},
            {"ce_specversion", "1.0"},
            {"ce_datacontenttype", "application/json"},
            {"ce_correlationid", "corr-1"},
            {"ce_time", "2024-01-15T10:30:00Z"}
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
      message = Consumer.to_message(kafka_message(), state())

      assert is_binary(message.id)
      assert message.id != ""
    end

    test "uses the kafka record timestamp when ce_time is missing" do
      ts = 1_700_000_000_000
      message = Consumer.to_message(kafka_message(ts: ts), state())

      assert message.timestamp == DateTime.from_unix!(ts, :millisecond)
    end

    test "applies defaults for missing CloudEvents headers" do
      message = Consumer.to_message(kafka_message(), state())

      assert message.spec_version == "1.0"
      assert message.content_type == "text/plain"
      assert message.source == URI.new!("https://hex.pm/packages/ming")
      assert message.type == nil
      assert message.correlation_id == nil
    end
  end

  describe "handle_message/2" do
    test "dispatches to the command processor and acks" do
      record = kafka_message(value: "hello", headers: [{"ce_id", "msg-ack"}])

      assert {:ok, :ack, state} = Consumer.handle_message(record, state())

      assert_receive {:consumed, %Message{payload: "hello", id: "msg-ack"}, opts}
      assert opts[:routing_key] == :ming_consume_message

      assert opts[:metadata] == %{
               routing_key: :order_created,
               command_process: TestKafkaProcessor
             }

      assert state.routing_key == :order_created
    end

    test "acks when the processor rejects the message" do
      Application.put_env(:ming, :kafka_test_response, {:ok, :reject})

      assert {:ok, :ack, _state} = Consumer.handle_message(kafka_message(), state())
      assert_receive {:consumed, %Message{}, _opts}
    end

    test "acks and logs an error when the processor requeues the message" do
      Application.put_env(:ming, :kafka_test_response, {:ok, :requeue})

      log =
        capture_log([level: :error], fn ->
          assert {:ok, :ack, _state} = Consumer.handle_message(kafka_message(), state())
        end)

      assert log =~ "Kafka does not support requeue"
      assert log =~ "acked"
      assert_receive {:consumed, %Message{}, _opts}
    end

    test "republishes requeued messages to the requeue routing key and acks" do
      Application.put_env(:ming, :kafka_test_response, {:ok, :requeue})

      assert {:ok, :ack, _state} =
               Consumer.handle_message(kafka_message(), state(requeue_routing_key: :orders_retry))

      assert_receive {:consumed, %Message{}, _opts}
      assert_receive {:posted, %Message{payload: "payload"}, :orders_retry}
    end

    test "forwards rejected messages to the dead letter queue and acks" do
      Application.put_env(:ming, :kafka_test_response, {:ok, :reject})

      assert {:ok, :ack, _state} =
               Consumer.handle_message(
                 kafka_message(),
                 state(dead_letter_queue_routing_key: :orders_dlq)
               )

      assert_receive {:consumed, %Message{}, _opts}

      assert_receive {:posted, %Message{} = dlq_message, :orders_dlq}
      assert dlq_message.headers["ORIGINAL_TOPIC"] == "orders"
      assert %DateTime{} = dlq_message.headers["ORIGINAL_TIMESTAMP"]
      assert Map.has_key?(dlq_message.headers, "ORIGINAL_TYPE")
    end

    test "acks rejected messages without a dead letter queue" do
      Application.put_env(:ming, :kafka_test_response, {:ok, :reject})

      log =
        capture_log([level: :error], fn ->
          assert {:ok, :ack, _state} = Consumer.handle_message(kafka_message(), state())
        end)

      assert log =~ "rejected message and no dead letter queue configured"
      assert_receive {:consumed, %Message{}, _opts}
      refute_receive {:posted, _, _}
    end

    test "forwards unaccepted messages to the invalid message routing key and acks" do
      Application.put_env(:ming, :kafka_test_response, {:ok, {:reject, :unaccepted}})

      assert {:ok, :ack, _state} =
               Consumer.handle_message(
                 kafka_message(),
                 state(invalid_message_routing_key: :orders_invalid)
               )

      assert_receive {:consumed, %Message{}, _opts}

      assert_receive {:posted, %Message{} = invalid_message, :orders_invalid}
      assert invalid_message.headers["ORIGINAL_TOPIC"] == "orders"
    end

    test "handles unaccepted messages returned bare by a halted pipeline" do
      Application.put_env(:ming, :kafka_test_response, {:reject, :unaccepted})

      assert {:ok, :ack, _state} =
               Consumer.handle_message(
                 kafka_message(),
                 state(invalid_message_routing_key: :orders_invalid)
               )

      assert_receive {:consumed, %Message{}, _opts}
      assert_receive {:posted, %Message{}, :orders_invalid}
    end

    test "falls back to the dead letter queue for unaccepted messages" do
      Application.put_env(:ming, :kafka_test_response, {:ok, {:reject, :unaccepted}})

      assert {:ok, :ack, _state} =
               Consumer.handle_message(
                 kafka_message(),
                 state(dead_letter_queue_routing_key: :orders_dlq)
               )

      assert_receive {:consumed, %Message{}, _opts}
      assert_receive {:posted, %Message{}, :orders_dlq}
    end

    test "acks and logs an error for unaccepted messages with no channel configured" do
      Application.put_env(:ming, :kafka_test_response, {:ok, {:reject, :unaccepted}})

      log =
        capture_log([level: :error], fn ->
          assert {:ok, :ack, _state} = Consumer.handle_message(kafka_message(), state())
        end)

      assert log =~ "unacceptable"
      assert_receive {:consumed, %Message{}, _opts}
      refute_receive {:posted, _, _}
    end

    test "acks when the processor fails" do
      Application.put_env(:ming, :kafka_test_response, {:error, :boom})

      assert {:ok, :ack, _state} = Consumer.handle_message(kafka_message(), state())
      assert_receive {:consumed, %Message{}, _opts}
    end
  end
end
