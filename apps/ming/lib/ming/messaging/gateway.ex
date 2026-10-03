defmodule Ming.Messaging.Gateway do
  @moduledoc """
  Behaviour for messaging gateway adapters.

  A gateway bridges a dispatcher to a message transport (an in-memory
  queue, AMQP, Kafka, ...), resolving the producer and consumer modules
  used for each declared publication and subscription.

  Besides this behaviour, a gateway adapter must be startable as a child
  of the dispatcher's supervision tree — that is, expose `start_link/1`
  (or a custom `child_spec/1`) accepting its configuration map, which
  includes the gateway `:name`. See `Ming.Messaging.InMemory.Gateway` for
  a reference implementation.
  """

  @doc """
  Returns the module implementing `Ming.Messaging.Producer` for the given
  publication configuration.
  """
  @callback producer(publication :: map()) :: module() | {:error, any()}

  @doc """
  Returns the module implementing `Ming.Messaging.Consumer` for the given
  subscription configuration.
  """
  @callback consumer(subscription :: map()) :: module() | {:error, any()}
end
