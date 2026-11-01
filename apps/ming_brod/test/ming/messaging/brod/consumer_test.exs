defmodule Ming.Messaging.Brod.ConsumerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Ming.Messaging.Brod
  alias Ming.Messaging.Brod.Buffer
  alias Ming.Messaging.Brod.Consumer
  alias Ming.Messaging.Message

  setup do
    gateway_name = Module.concat(Brod, "Gw#{System.unique_integer([:positive])}")

    start_supervised!({Registry, keys: :unique, name: Brod.registry_name(gateway_name)})

    %{gateway_name: gateway_name}
  end

  defp start_buffer(gateway_name, subscription) do
    buffer_name = Brod.buffer_name(Map.put(subscription, :gateway_name, gateway_name))
    start_supervised!(%{id: buffer_name, start: {Buffer, :start_link, [[name: buffer_name]]}})
    buffer_name
  end

  defp start_consumer(gateway_name, subscription, processor, buffer) do
    subscription = Map.put(subscription, :gateway_name, gateway_name)

    start_supervised!(
      {Consumer,
       name: Brod.consumer_name(subscription, 1),
       buffer: buffer,
       processor: processor,
       subscription: subscription}
    )
  end

  defp message(meta \\ nil) do
    %Message{
      id: "msg-1",
      payload: "payload",
      routing_key: "test",
      timestamp: DateTime.utc_now(),
      headers: if(meta, do: %{ming_brod: meta}, else: %{})
    }
  end

  test "receive_messages takes messages from the subscription buffer", %{gateway_name: gateway} do
    subscription = %{name: :sub, routing_key: "test"}
    buffer = start_buffer(gateway, subscription)

    Buffer.push(buffer, :one)
    Buffer.push(buffer, :two)

    subscription = Map.put(subscription, :gateway_name, gateway)
    assert Consumer.receive_messages(subscription) == [:one, :two]
  end

  test "receive_messages respects :buffer_size and :receive_timeout", %{gateway_name: gateway} do
    subscription = %{name: :sub, routing_key: "test", buffer_size: 2, receive_timeout: 50}
    buffer = start_buffer(gateway, subscription)

    for item <- 1..5, do: Buffer.push(buffer, item)

    subscription = Map.put(subscription, :gateway_name, gateway)
    assert Consumer.receive_messages(subscription) == [1, 2]
    assert Consumer.receive_messages(subscription) == [3, 4]
    assert Consumer.receive_messages(subscription) == [5]
    assert Consumer.receive_messages(subscription) == []
  end

  test "receive_messages returns an error when the buffer is not available", %{
    gateway_name: gateway
  } do
    subscription = %{gateway_name: gateway, name: :missing, routing_key: "test"}

    assert {:error, _reason} = Consumer.receive_messages(subscription)
  end

  test "the GenServer drains buffered messages into the processor mailbox", %{
    gateway_name: gateway
  } do
    subscription = %{name: :sub_drain, routing_key: "test", receive_timeout: 10}
    buffer = start_buffer(gateway, subscription)
    Process.register(self(), :brod_consumer_test_drain_processor)

    start_consumer(gateway, subscription, :brod_consumer_test_drain_processor, buffer)

    Buffer.push(buffer, :one)
    Buffer.push(buffer, :two)

    assert_receive {:ming_message, :one}, 500
    assert_receive {:ming_message, :two}, 500
  end

  test "the GenServer leaves the buffer untouched while the processor is missing", %{
    gateway_name: gateway
  } do
    subscription = %{
      name: :sub_wait,
      routing_key: "test",
      receive_timeout: 10,
      empty_delay: 10
    }

    buffer = start_buffer(gateway, subscription)
    Buffer.push(buffer, :one)

    start_consumer(gateway, subscription, :brod_consumer_test_no_such_processor, buffer)

    Process.sleep(50)
    assert Buffer.take(buffer, 10, 0) == [:one]
  end

  test "the GenServer starts draining once the processor registers", %{gateway_name: gateway} do
    subscription = %{
      name: :sub_late,
      routing_key: "test",
      receive_timeout: 10,
      empty_delay: 10
    }

    buffer = start_buffer(gateway, subscription)
    Buffer.push(buffer, :one)

    start_consumer(gateway, subscription, :brod_consumer_test_late_processor, buffer)

    Process.register(self(), :brod_consumer_test_late_processor)

    assert_receive {:ming_message, :one}, 500
  end

  test "ack is a no-op without brod metadata" do
    assert Consumer.ack(%{}, message()) == :ok
  end

  test "ack releases the prefetch window and marks the offset for commit" do
    test_pid = self()
    worker = spawn(fn -> Process.sleep(:infinity) end)

    meta = %{
      partition: 0,
      offset: 42,
      worker: worker,
      ack_fun: fn offset -> send(test_pid, {:acked, offset}) end
    }

    assert Consumer.ack(%{}, message(meta)) == :ok
    assert_received {:acked, 42}
  end

  test "nack settles the message as acknowledged" do
    test_pid = self()

    meta = %{
      partition: 0,
      offset: 7,
      worker: spawn(fn -> Process.sleep(:infinity) end),
      ack_fun: fn offset -> send(test_pid, {:acked, offset}) end
    }

    log =
      capture_log(fn ->
        assert Consumer.nack(%{name: :sub}, message(meta)) == :ok
      end)

    assert log =~ "Kafka does not support rejecting (nack) messages"
    assert_received {:acked, 7}
  end

  test "defer settles the message as acknowledged" do
    test_pid = self()

    meta = %{
      partition: 0,
      offset: 9,
      worker: spawn(fn -> Process.sleep(:infinity) end),
      ack_fun: fn offset -> send(test_pid, {:acked, offset}) end
    }

    log =
      capture_log(fn ->
        assert Consumer.defer(%{name: :sub}, message(meta), 1_000) == :ok
      end)

    assert log =~ "Kafka does not support deferred redelivery"
    assert_received {:acked, 9}
  end
end
