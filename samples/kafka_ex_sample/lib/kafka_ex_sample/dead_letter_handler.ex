defmodule KafkaExSample.DeadLetterHandler do
  @moduledoc """
  Handler invoked for messages consumed from the "orders.dlq" topic, i.e.
  orders that `KafkaExSample.OrderHandler` rejected.

  The forwarded message keeps the original payload and carries
  `ORIGINAL_TIMESTAMP`, `ORIGINAL_TOPIC` and `ORIGINAL_TYPE` headers.
  """

  require Logger

  alias Ming.Context

  @behaviour Ming.Handler

  @impl Ming.Handler
  def handle(request, %Context{} = context) do
    Logger.warning(
      "dead lettered #{inspect(context.metadata[:routing_key])}: #{inspect(request)} " <>
        "(correlation_id: #{context.correlation_id})"
    )

    :ok
  end
end
