defmodule Ming.Message.Router do
  @moduledoc """
  Built-in router for messaging-related routing keys.

  This router is automatically included by `Ming.CommandProcessor` and
  provides the internal pipelines used to produce and consume
  `%Ming.Message{}` structs through configured messaging gateways.

  ## Routes

  - `:ming_produce_message` — converts a domain request into a
    `%Ming.Message{}` and publishes it via a gateway producer.
  - `:ming_consume_message` — converts an incoming `%Ming.Message{}`
    back into a domain request and dispatches it through the command
    processor pipeline.
  """

  use Ming.Router

  register(:ming_produce_message,
    middleware: [
      Ming.Message.Middleware.ResolvePublication,
      Ming.Message.Middleware.EncodeRequestAsMessage,
      Ming.Message.Middleware.ApplyPublicationDefaults
    ],
    handler: Ming.Message.ProducerMessageHandler
  )

  register(:ming_consume_message,
    middleware: [
      Ming.Message.Middleware.DecodeMessageToRequest,
      Ming.Message.Middleware.DecodeCloudEventPayload
    ],
    handler: Ming.Message.ProducerMessageHandler
  )
end
