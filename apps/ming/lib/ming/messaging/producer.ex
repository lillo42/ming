defmodule Ming.Messaging.Producer do
  alias Ming.Context
  alias Ming.Messaging.Message

  @callback produce(message :: Message.t(), context :: Context.t()) :: :ok | {:error, any()}
end
