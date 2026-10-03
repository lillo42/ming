defmodule Ming.Messaging.InMemory.Consumer do
  @moduledoc """
  Polls the queue resolved from the subscription's `:queue` option,
  defaulting to its `:routing_key`.

  Messages are removed from the queue as they are polled, so `ack/2` and
  `nack/2` are no-ops and delivery is at-most-once. `defer/3` re-enqueues
  the message, optionally after a delay.
  """
  @behaviour Ming.Messaging.Consumer

  alias Ming.Messaging.InMemory.Queue

  @impl Ming.Messaging.Consumer
  def receive_messages(subscription),
    do: Queue.poll(queue_name(subscription), Map.get(subscription, :buffer_size, 10))

  @impl Ming.Messaging.Consumer
  def ack(_subscription, _message), do: :ok

  @impl Ming.Messaging.Consumer
  def nack(_subscription, _message), do: :ok

  @impl Ming.Messaging.Consumer
  def defer(subscription, message, 0), do: Queue.push(queue_name(subscription), message)

  def defer(subscription, message, delay),
    do: Queue.push(queue_name(subscription), message, delay)

  defp queue_name(subscription),
    do: Map.get(subscription, :queue) || Map.fetch!(subscription, :routing_key)
end
