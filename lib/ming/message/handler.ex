defmodule Ming.Message.Handler do
  @moduledoc """
  Handler that publishes a %Ming.Message{} via a configured producer.

  Expects the context assigns to include:
  - `:ming_message_producer` — a module implementing `Ming.Message.Producer`
  - `:ming_message_publication` — publication options for the producer
  """

  alias Ming.Context
  alias Ming.Message

  @behaviour Ming.Handler

  @impl Ming.Handler
  def handle(
        %Message{} = request,
        %Context{
          assigns:
            %{
              ming_message_producer: producer,
              ming_message_gateway: gateway,
              ming_message_publication: publication
            } = assigns,
          metadata: metadata
        }
      ) do
    extra_opts = Map.get(metadata, :producer_opts, [])

    producer.publish(request,
      gateway: gateway,
      publication: publication,
      extra_opts: extra_opts
    )
  end
end
