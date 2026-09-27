defmodule Ming.Messaging.ProduceHandler do
  @moduledoc """
  Terminal handler of the `:ming_post_message` pipeline.

  Resolves the gateway producer for the publication stored in the context
  metadata (`:ming_publication`) and produces the encoded message through
  it. Returns `{:error, :producer_not_found}` when the publication or its
  gateway cannot be resolved.
  """

  @behaviour Ming.Handler

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Handler
  def handle(%Message{} = message, %Context{} = context) do
    with publication when not is_nil(publication) <- context.metadata[:ming_publication],
         dispatcher when not is_nil(dispatcher) <- context.metadata[:ming_dispatcher],
         gateway when not is_nil(gateway) <- gateway(dispatcher, publication) do
      gateway.adapter.producer(publication).produce(message, context)
    else
      _ -> {:error, :producer_not_found}
    end
  end

  defp gateway(dispatcher, publication) do
    dispatcher.config()[:gateways][publication.gateway_name]
  end
end
