defmodule Ming.Messaging.Consumer do
  alias Ming.Messaging.Message

  @callback receive_messages(subscription :: Keyword.t()) :: [Message.t()] | {:error, any()}

  @callback ack(subscription :: Keyword.t(), Message.t()) :: :ok | {:error, any()}

  @callback nack(subscription :: Keyword.t(), Message.t()) :: :ok | {:error, any()}

  @callback defer(subscription :: Keyword.t(), Message.t(), delay :: timeout()) ::
              :ok | {:error, any()}
end
