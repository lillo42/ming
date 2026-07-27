defmodule RabbitMQSample.OrderHandler do
  @moduledoc """
  Handler invoked for every message consumed from RabbitMQ.

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
    #   :ok / {:ok, _} -> ack, :reject -> reject (no requeue),
    #   :requeue -> reject with requeue, {:error, _} -> reject (no requeue)
    :ok
  end
end
