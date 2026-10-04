defmodule Ming.Messaging.Brod.Consumer do
  @moduledoc """
  Polls the subscription's `Ming.Messaging.Brod.Buffer`, which is fed by
  the subscription's `:brod_group_subscriber_v2`.

  `receive_messages/1` blocks up to `:receive_timeout` milliseconds
  (default 5s) waiting for messages, so an idle subscription costs no
  polling wakeups; it returns `{:error, reason}` when the buffer is not
  available.

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
