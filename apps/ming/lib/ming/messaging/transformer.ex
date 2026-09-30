defmodule Ming.Messaging.Transformer do
  alias Ming.Context
  alias Ming.Messaging.Message

  @callback encode(message :: Message.t(), args :: any(), context :: Context.t()) ::
              Message.t()
              | {:ok, Message.t()}
              | Context.t()
              | {:error, any()}

  @callback decode(message :: Message.t(), args :: any(), context :: Context.t()) ::
              Message.t()
              | {:ok, Message.t()}
              | Context.t()
              | {:error, any()}
end
