defmodule Ming.Messaging.Producer do
  @moduledoc """
  Behaviour for publishing `%Ming.Messaging.Message{}` structs to a
  transport.

  Implementations are resolved by the gateway adapter (see
  `Ming.Messaging.Gateway`) and invoked by
  `Ming.Messaging.ProduceHandler` with the publication stored in the
  context metadata (`:ming_publication`).
  """

  alias Ming.Context
  alias Ming.Messaging.Message

  @doc """
  Publishes the message through the transport bound to the context's
  publication.
  """
  @callback produce(message :: Message.t(), context :: Context.t()) :: :ok | {:error, any()}
end
