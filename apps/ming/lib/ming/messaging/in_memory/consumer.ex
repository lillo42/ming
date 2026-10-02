defmodule Ming.Messaging.InMemory.Consumer do
  @behaviour Ming.Messaging.Consumer

  alias Ming.Messaging.InMemory.Queue

  @impl Ming.Messaging.Consumer
  def receive_messages(%{queue: queue, buffer_size: buffer_size}),
    do: Queue.poll(queue, buffer_size)

  @impl Ming.Messaging.Consumer
  def ack(_subscription, _message), do: :ok

  @impl Ming.Messaging.Consumer
  def nack(_subscription, _message), do: :ok

  @impl Ming.Messaging.Consumer
  def defer(%{queue: queue}, message, 0), do: Queue.push(queue, message)

  def defer(%{queue: queue}, message, delay), do: Queue.push(queue, message, delay)
end
