defmodule Ming.Messaging.Mapper do
  alias Ming.Context
  alias Ming.Messaging.Message

  @callback to_message(request :: any(), context :: Context.t()) ::
              Message.t()
              | Context.t()
              | {:ok, Message.t()}
              | {:error, any()}

  @callback to_request(message :: Message.t(), context :: Context.t()) ::
              any()
              | Context.t()
              | {:ok, any()}
              | {:error, any()}
end
