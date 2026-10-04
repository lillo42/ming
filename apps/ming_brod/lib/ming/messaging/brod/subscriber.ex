defmodule Ming.Messaging.Brod.Subscriber do
  @moduledoc """
  `:brod_group_subscriber_v2` callback module.

  One worker process per assigned topic-partition calls
  `handle_message/2` for each Kafka message; the message is decoded by
  `Ming.Messaging.Brod.Decoder` and pushed into the subscription's
  `Ming.Messaging.Brod.Buffer`.

  The callback returns `{:ok, state}` — it never acks — so both the
  partition consumer's prefetch window and the group's offset commits
  only advance when `Ming.Messaging.Brod.Consumer.ack/2` settles the
  message (at-least-once delivery). The worker pid and the offset
  `ack_fun` ride on each message's `headers[:ming_brod]` so the consumer
  can release the prefetch window via `:brod_topic_subscriber.ack/3` and
  mark the offset for commit.

  The buffer name and routing key arrive through the subscriber config's
  `:init_data`.
  """
  @behaviour :brod_group_subscriber_v2

  alias Ming.Messaging.Brod.Buffer
  alias Ming.Messaging.Brod.Decoder

  @impl true
  def init(init_info, init_data) do
    {:ok,
     %{
       buffer: Map.fetch!(init_data, :buffer),
       routing_key: Map.fetch!(init_data, :routing_key),
       topic: init_info.topic,
       partition: init_info.partition,
       ack_fun: init_info.ack_fun
     }}
  end

  @impl true
  def handle_message(message, state) do
    decoded =
      Decoder.to_message(message, %{
        topic: state.topic,
        partition: state.partition,
        routing_key: state.routing_key,
        worker: self(),
        ack_fun: state.ack_fun
      })

    Buffer.push(state.buffer, decoded)

    {:ok, state}
  end
end
