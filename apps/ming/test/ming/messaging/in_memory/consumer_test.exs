defmodule Ming.Messaging.InMemory.ConsumerTest do
  use ExUnit.Case, async: false

  alias Ming.Messaging.InMemory.Consumer
  alias Ming.Messaging.InMemory.Queue

  test "receive_messages polls the queue resolved from the routing key" do
    start_supervised!({Queue, name: :consumer_test_rk})

    Queue.push(:consumer_test_rk, :one)
    Queue.push(:consumer_test_rk, :two)

    assert Consumer.receive_messages(%{routing_key: :consumer_test_rk}) == [:one, :two]
  end

  test "receive_messages resolves the queue from the :queue option" do
    start_supervised!({Queue, name: :consumer_test_explicit})

    Queue.push(:consumer_test_explicit, :item)

    subscription = %{routing_key: :consumer_test_rk_unused, queue: :consumer_test_explicit}
    assert Consumer.receive_messages(subscription) == [:item]
  end

  test "receive_messages respects :buffer_size and defaults to 10" do
    start_supervised!({Queue, name: :consumer_test_buffer})

    for item <- 1..15, do: Queue.push(:consumer_test_buffer, item)

    subscription = %{routing_key: :consumer_test_buffer}
    assert Consumer.receive_messages(subscription) == Enum.to_list(1..10)

    subscription = %{routing_key: :consumer_test_buffer, buffer_size: 2}
    assert Consumer.receive_messages(subscription) == [11, 12]
  end

  test "receive_messages on a missing queue returns an error" do
    assert Consumer.receive_messages(%{routing_key: :consumer_test_missing}) ==
             {:error, {:queue_not_found, :consumer_test_missing}}
  end

  test "ack and nack are no-ops" do
    assert Consumer.ack(%{}, :message) == :ok
    assert Consumer.nack(%{}, :message) == :ok
  end

  test "acked messages are not redelivered" do
    start_supervised!({Queue, name: :consumer_test_ack})

    Queue.push(:consumer_test_ack, :one)

    subscription = %{routing_key: :consumer_test_ack}
    assert Consumer.receive_messages(subscription) == [:one]
    assert :ok = Consumer.ack(subscription, :one)
    assert Consumer.receive_messages(subscription) == []
  end

  test "nacked messages are not redelivered" do
    start_supervised!({Queue, name: :consumer_test_nack})

    Queue.push(:consumer_test_nack, :one)

    subscription = %{routing_key: :consumer_test_nack}
    assert Consumer.receive_messages(subscription) == [:one]
    assert :ok = Consumer.nack(subscription, :one)
    assert Consumer.receive_messages(subscription) == []
  end

  test "subscriptions sharing a queue compete for messages" do
    start_supervised!({Queue, name: :consumer_test_competing})

    Queue.push(:consumer_test_competing, :one)

    first = %{name: :first, routing_key: :consumer_test_competing}
    second = %{name: :second, routing_key: :consumer_test_competing}

    results = [Consumer.receive_messages(first), Consumer.receive_messages(second)]

    assert Enum.sort(results) == [[], [:one]]
  end

  test "defer with delay 0 re-enqueues immediately" do
    start_supervised!({Queue, name: :consumer_test_defer_now})

    assert :ok = Consumer.defer(%{routing_key: :consumer_test_defer_now}, :again, 0)
    assert Queue.take(:consumer_test_defer_now, 10) == [:again]
  end

  test "defer with a delay re-enqueues after the delay" do
    start_supervised!({Queue, name: :consumer_test_defer_later})

    assert :ok = Consumer.defer(%{routing_key: :consumer_test_defer_later}, :again, 20)
    assert Queue.take(:consumer_test_defer_later, 10) == []

    Process.sleep(100)
    assert Queue.take(:consumer_test_defer_later, 10) == [:again]
  end

  test "the GenServer drains queued messages into the processor mailbox" do
    start_supervised!({Queue, name: :consumer_test_drain})
    Process.register(self(), :consumer_test_drain_processor)

    start_supervised!(
      {Consumer,
       name: :consumer_test_drain_consumer,
       queue: :consumer_test_drain,
       processor: :consumer_test_drain_processor,
       subscription: %{buffer_size: 5}}
    )

    Queue.push(:consumer_test_drain, :one)
    Queue.push(:consumer_test_drain, :two)

    assert_receive {:ming_message, :one}, 500
    assert_receive {:ming_message, :two}, 500
  end

  test "the GenServer leaves the queue untouched while the processor is missing" do
    start_supervised!({Queue, name: :consumer_test_waiting})
    Queue.push(:consumer_test_waiting, :one)

    start_supervised!(
      {Consumer,
       name: :consumer_test_waiting_consumer,
       queue: :consumer_test_waiting,
       processor: :consumer_test_no_such_processor,
       subscription: %{}}
    )

    Process.sleep(50)
    assert Queue.take(:consumer_test_waiting, 10) == [:one]
  end

  test "the GenServer starts draining once the processor registers" do
    start_supervised!({Queue, name: :consumer_test_late})
    Queue.push(:consumer_test_late, :one)

    start_supervised!(
      {Consumer,
       name: :consumer_test_late_consumer,
       queue: :consumer_test_late,
       processor: :consumer_test_late_processor,
       subscription: %{}}
    )

    Process.register(self(), :consumer_test_late_processor)

    assert_receive {:ming_message, :one}, 500
  end
end
