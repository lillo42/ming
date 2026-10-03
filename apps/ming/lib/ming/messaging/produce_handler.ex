defmodule Ming.Messaging.ProduceHandler do
  @moduledoc """
  Terminal handler of the `:ming_post_message` pipeline.

  Resolves the gateway producer for the publication stored in the context
  metadata (`:ming_publication`) and produces the encoded message through
  it. Returns `{:error, :producer_not_found}` when the publication or its
  gateway cannot be resolved.

  ## Telemetry

  Producing emits a `[:ming, :produce]` span (`:start`/`:stop`/`:exception`
  events) with metadata `:gateway`, `:routing_key`, `:queue`, `:message_id`
  and `:correlation_id`; the `:stop` event adds the `:result` of the
  producer callback.
  """

  @behaviour Ming.Handler

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Handler
  def handle(%Message{} = message, %Context{} = context) do
    with publication when not is_nil(publication) <- context.metadata[:ming_publication],
         dispatcher when not is_nil(dispatcher) <- context.metadata[:ming_dispatcher],
         gateway when not is_nil(gateway) <- gateway(dispatcher, publication) do
      produce(gateway.adapter, message, publication, context)
    else
      _ -> {:error, :producer_not_found}
    end
  end

  defp produce(adapter, message, publication, context) do
    metadata = %{
      gateway: publication[:gateway_name],
      routing_key: context.metadata[:ming_routing_key] || context.routing_key,
      queue: publication[:queue] || publication[:routing_key],
      message_id: message.id,
      correlation_id: message.correlation_id
    }

    :telemetry.span([:ming, :produce], metadata, fn ->
      result = adapter.producer(publication).produce(message, context)
      {result, Map.put(metadata, :result, result)}
    end)
  end

  defp gateway(dispatcher, publication) do
    dispatcher.config()[:gateways][publication.gateway_name]
  end
end
