defmodule Ming.Messaging.InMemory.Producer do
  @moduledoc """
  Publishes messages onto the queue resolved from the publication's
  `:queue` option, defaulting to its `:routing_key`.

  Returns `{:error, {:queue_not_found, queue}}` when the queue process is
  not running, so `Ming.Dispatcher`'s `post/2` surfaces the failure
  instead of silently dropping the message.
  """
  @behaviour Ming.Messaging.Producer

  alias Ming.Context
  alias Ming.Messaging.Message

  alias Ming.Messaging.InMemory.Queue

  @impl Ming.Messaging.Producer
  def produce(%Message{} = message, %Context{metadata: %{ming_publication: publication}}),
    do: Queue.push(publication[:queue] || publication[:routing_key], message)
end
