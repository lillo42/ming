defmodule KafkaExSample.OrderHandler do
  @moduledoc """
  Handler invoked for every message consumed from the "orders" topic.

  Orders with a negative amount are rejected, which makes the gateway forward
  them to the publication named by the subscription's
  `:dead_letter_queue_routing_key` option ("orders.dlq" topic).

  Messages whose payload cannot be decoded never reach this handler: the
  consume pipeline rejects them as `:unaccepted` and the gateway forwards
  them to the publication named by `:invalid_message_routing_key`
  ("orders.invalid" topic) instead.
  """

  require Logger

  alias Ming.Context

  @behaviour Ming.Handler

  @impl Ming.Handler
  def handle(%{"amount" => amount} = request, %Context{} = context) when amount < 0 do
    Logger.warning(
      "rejecting order with negative amount: #{inspect(request)} " <>
        "(routing_key: #{inspect(context.metadata[:routing_key])})"
    )

    # Kafka has no native reject: the gateway forwards the message to the
    # dead letter publication and commits the offset.
    :reject
  end

  def handle(request, %Context{} = context) do
    Logger.info(
      "consumed #{inspect(context.metadata[:routing_key])}: #{inspect(request)} " <>
        "(correlation_id: #{context.correlation_id})"
    )

    :ok
  end
end
