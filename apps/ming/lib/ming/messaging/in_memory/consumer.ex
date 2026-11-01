defmodule Ming.Messaging.InMemory.Consumer do
  use GenServer

  @moduledoc """
  Polls the queue resolved from the subscription's `:queue` option,
  defaulting to its `:routing_key`, and pushes each batch into the
  subscription's `Ming.Messaging.Processor`.

  As a `GenServer` it drains its queue continuously: after a non-empty
  batch it drains again immediately, and when the queue or the processor
  is unavailable it retries after `:empty_delay` (default 10ms). If the
  processor is not registered yet the queue is left untouched, so no
  messages are lost while the processor is starting or restarting.

  Messages are removed from the queue as they are polled, so `ack/2` and
  `nack/2` are no-ops and delivery is at-most-once. `defer/3` re-enqueues
  the message, optionally after a delay.
  """
  @behaviour Ming.Messaging.Consumer

  alias Ming.Messaging.Processor
  alias Ming.Messaging.InMemory.Queue

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @impl true
  def init(opts) do
    subscription = Keyword.fetch!(opts, :subscription)

    {:ok,
     %{
       queue: Keyword.get(opts, :queue) || queue_name(subscription),
       processor: Keyword.fetch!(opts, :processor),
       subscription: subscription
     }, {:continue, :work}}
  end

  @impl true
  def handle_continue(:work, state), do: work(state)

  @impl true
  def handle_info(:work, state), do: work(state)

  defp work(%{queue: queue, processor: processor, subscription: subscription} = state) do
    empty_delay = Map.get(subscription, :empty_delay, 10)

    delay =
      if Process.whereis(processor) do
        drain(queue, processor, subscription, empty_delay)
      else
        empty_delay
      end

    schedule_work(delay)
    {:noreply, state}
  end

  defp drain(queue, processor, subscription, empty_delay) do
    case Queue.take(queue, Map.get(subscription, :buffer_size, 10)) do
      {:error, _reason} -> empty_delay
      [] -> empty_delay
      messages -> if push(processor, queue, messages), do: 0, else: empty_delay
    end
  end

  # The processor can vanish between the whereis check and the push when it
  # restarts; re-enqueue the drained messages and retry later.
  defp push(processor, queue, messages) do
    Processor.push(processor, messages)
    true
  rescue
    ArgumentError ->
      Enum.each(messages, &Queue.push(queue, &1))
      false
  end

  defp schedule_work(0), do: send(self(), :work)
  defp schedule_work(delay), do: Process.send_after(self(), :work, delay)

  @impl Ming.Messaging.Consumer
  def receive_messages(subscription) do
    buffer_size = Map.get(subscription, :buffer_size, 10)
    Queue.take(queue_name(subscription), buffer_size)
  end

  @impl Ming.Messaging.Consumer
  def ack(_subscription, _message), do: :ok

  @impl Ming.Messaging.Consumer
  def nack(_subscription, _message), do: :ok

  @impl Ming.Messaging.Consumer
  def defer(subscription, message, 0), do: Queue.push(queue_name(subscription), message)

  def defer(subscription, message, delay) do
    Queue.push(queue_name(subscription), message, delay)
  end

  defp queue_name(subscription) do
    Map.get(subscription, :queue) || Map.fetch!(subscription, :routing_key)
  end
end
