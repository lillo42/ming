defmodule Ming.Messaging.InMemory.Producer do
  @behaviour Ming.Messaging.Producer

  alias Ming.Context
  alias Ming.Messaging.Message

  alias Ming.Messaging.InMemory.Queue

  @impl Ming.Messaging.Producer
  def produce(%Message{} = message, %Context{metadata: %{ming_publication: publication}}),
    do: Queue.push(publication.queue, message)
end
