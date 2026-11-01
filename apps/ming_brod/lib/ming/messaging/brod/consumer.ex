defmodule Ming.Messaging.Brod.Consumer do
  use GenServer

  @moduledoc """
  Drains the subscription's `Ming.Messaging.Brod.Buffer` (fed by the
  subscription's `:brod_group_subscriber_v2`) and pushes each batch into
  the subscription's `Ming.Messaging.Processor`.

  As a `GenServer` it takes from the buffer continuously: `take/3`
  blocks up to `:receive_timeout` (default 5s) waiting for messages, so
  an idle subscription costs no polling wakeups. When the buffer is
  unavailable it retries after `:failure_delay` (default 5s); when the
  processor is not registered yet the buffer is left untouched and
  retried after `:empty_delay` (default 10ms), so no messages are lost
  while the processor is starting or restarting.

  Settlement is at-least-once:

    * `ack/2` releases the partition's prefetch window
      (`:brod_topic_subscriber.ack/3`) and marks the offset for the
      group's periodic commit (`:brod_group_subscriber_v2.ack/4`)
    * `nack/2` settles the same way — Kafka has no reject, so the
      message is simply not redelivered
    * `defer/3` also settles as acknowledged — Kafka has no deferred
      redelivery, so the message is not redelivered (a warning is
      logged)

  The Kafka coordinates for settlement travel on the message's
  `headers[:ming_brod]` (see `Ming.Messaging.Brod.Decoder`).
  """
  @behaviour Ming.Messaging.Consumer

  require Logger

  alias Ming.Messaging.Brod
  alias Ming.Messaging.Brod.Buffer
  alias Ming.Messaging.Processor

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       buffer: Keyword.fetch!(opts, :buffer),
       processor: Keyword.fetch!(opts, :processor),
       subscription: Keyword.fetch!(opts, :subscription)
     }, {:continue, :work}}
  end

  @impl true
  def handle_continue(:work, state), do: work(state)

  @impl true
  def handle_info(:work, state), do: work(state)

  defp work(%{buffer: buffer, processor: processor, subscription: subscription} = state) do
    delay =
      if Process.whereis(processor) do
        drain(buffer, processor, subscription)
      else
        Map.get(subscription, :empty_delay, 10)
      end

    schedule_work(delay)
    {:noreply, state}
  end

  defp drain(buffer, processor, subscription) do
    case take(buffer, subscription) do
      {:error, _reason} -> failure_delay(subscription)
      [] -> 0
      messages -> if push(processor, buffer, messages), do: 0, else: failure_delay(subscription)
    end
  end

  defp failure_delay(subscription), do: Map.get(subscription, :failure_delay, 5_000)

  defp take(buffer, subscription) do
    count = Map.get(subscription, :buffer_size, 10)
    wait = Map.get(subscription, :receive_timeout, 5_000)

    Buffer.take(buffer, count, wait)
  catch
    :exit, reason -> {:error, reason}
  end

  # The processor can vanish between the whereis check and the push when
  # it restarts; re-enqueue the drained messages and retry later.
  defp push(processor, buffer, messages) do
    Processor.push(processor, messages)
    true
  rescue
    ArgumentError ->
      Enum.each(messages, &Buffer.push(buffer, &1))
      false
  end

  defp schedule_work(0), do: send(self(), :work)
  defp schedule_work(delay), do: Process.send_after(self(), :work, delay)

  @impl Ming.Messaging.Consumer
  def receive_messages(subscription) do
    buffer = Brod.buffer_name(subscription)
    count = Map.get(subscription, :buffer_size, 10)
    wait = Map.get(subscription, :receive_timeout, 5_000)

    try do
      Buffer.take(buffer, count, wait)
    catch
      :exit, reason -> {:error, reason}
    end
  end

  @impl Ming.Messaging.Consumer
  def ack(_subscription, message) do
    case brod_meta(message) do
      nil ->
        :ok

      %{partition: partition, offset: offset, worker: worker, ack_fun: ack_fun} ->
        :brod_topic_subscriber.ack(worker, partition, offset)
        ack_fun.(offset)
        :ok
    end
  end

  @impl Ming.Messaging.Consumer
  def nack(subscription, message) do
    Logger.warning(
      "Kafka does not support rejecting (nack) messages; settling message #{message.id} " <>
        "of subscription #{inspect(subscription[:name])} as acknowledged — " <>
        "the offset is committed and the message will not be redelivered"
    )

    ack(subscription, message)
  end

  @impl Ming.Messaging.Consumer
  def defer(subscription, message, delay) do
    Logger.warning(
      "Kafka does not support deferred redelivery; settling message #{message.id} " <>
        "of subscription #{inspect(subscription[:name])} as acknowledged instead of " <>
        "deferring it for #{delay}ms — the offset is committed and the message " <>
        "will not be redelivered"
    )

    ack(subscription, message)
  end

  defp brod_meta(message), do: Map.get(message.headers, :ming_brod)
end
