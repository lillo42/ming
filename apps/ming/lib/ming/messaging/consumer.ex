defmodule Ming.Messaging.Consumer do
  alias Ming.Messaging.Message

  @callback receive_messages(subscription :: map()) :: [Message.t()] | {:error, any()}

  @callback ack(subscription :: map(), message :: Message.t()) :: :ok | {:error, any()}

  @callback nack(subscription :: map(), message :: Message.t()) :: :ok | {:error, any()}

  @callback defer(subscription :: map(), message :: Message.t(), delay :: timeout()) ::
              :ok | {:error, any()}
end
