defmodule Ming.Message.Router do
  use Ming.Router

  middleware(Ming.Message.Middleware.SetGatewayPublication)
  middleware(Ming.Message.Middleware.RequestToMessage)
  middleware(Ming.Message.Middleware.UpdateMessageFromConfig)

  register(:ming_message,
    middleware: [
      Ming.Message.Middleware.SetGatewayPublication,
      Ming.Message.Middleware.RequestToMessage,
      Ming.Message.Middleware.UpdateMessageFromConfig
    ],
    handler: Ming.Message.Handler
  )
end
