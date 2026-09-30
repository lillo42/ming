defmodule Ming.Messaging.Handlers.Producer do
  @behaviour Ming.Handler

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Handler
  def handle(%Message{} = request, %Context{metadata: %{ming_publication: publication}} = context) do
    producer = publication.producer

    producer.produce(request, context)
  end
end
