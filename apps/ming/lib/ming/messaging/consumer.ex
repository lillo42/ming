defmodule Ming.Messaging.Consumer do
  @moduledoc """
  Behaviour for consuming `%Ming.Messaging.Message{}` structs from a
  transport.

  Batches of consumed messages are dispatched through the dispatcher's
  consume pipeline by `Ming.Messaging.Processor` and, after each message
  is processed, settled through `ack/2`, `nack/2` or `defer/3` according
  to the handler result (see `Ming.Messaging.BatchProcessing` for the
  settlement rules).
  """

  alias Ming.Messaging.Message

  @doc """
  Returns a batch of messages for the subscription, an empty list when
  none are available, or `{:error, reason}` on failure.
  """
  @callback receive_messages(subscription :: map()) :: [Message.t()] | {:error, any()}

  @doc """
  Settles a successfully processed message.
  """
  @callback ack(subscription :: map(), message :: Message.t()) :: :ok | {:error, any()}

  @doc """
  Settles a rejected message; it is not redelivered.
  """
  @callback nack(subscription :: map(), message :: Message.t()) :: :ok | {:error, any()}

  @doc """
  Redelivers the message after `delay` milliseconds (`0` redelivers
  immediately).
  """
  @callback defer(subscription :: map(), message :: Message.t(), delay :: timeout()) ::
              :ok | {:error, any()}
end
