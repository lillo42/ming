defmodule Ming.Messaging.Handlers.Producer do
  @moduledoc """
  Legacy terminal handler of the `:ming_post_message` pipeline.

  Superseded by `Ming.Messaging.ProduceHandler`, which resolves the
  producer from the gateway configuration at runtime instead of reading a
  `:producer` key from the publication.
  """
  @behaviour Ming.Handler

  alias Ming.Context
  alias Ming.Messaging.Message

  @impl Ming.Handler
  def handle(%Message{} = request, %Context{metadata: %{ming_publication: publication}} = context) do
    producer = publication.producer

    producer.produce(request, context)
  end
end
