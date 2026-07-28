defmodule KafkaSample.OrderHandler do
  @moduledoc """
  Handler invoked for every message consumed from Kafka.

  The payload arrives JSON-decoded (a plain map), and `context.metadata` keeps
  the subscription `:routing_key` that matched the message.
  """

  require Logger

  alias Ming.Context

  @behaviour Ming.Handler

  @impl Ming.Handler
  def handle(request, %Context{} = context) do
    Logger.info(
      "consumed #{inspect(context.metadata[:routing_key])}: #{inspect(request)} " <>
        "(correlation_id: #{context.correlation_id})"
    )

    # Return values map to broker acks:
    #   :ok / {:ok, _} -> ack, :reject -> ack (skip), :requeue -> ack plus an
    #   error log (Kafka has no requeue), {:error, _} -> ack (skip)
    :ok
  end
end
