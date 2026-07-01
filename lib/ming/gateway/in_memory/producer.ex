defmodule Ming.Gateway.InMemory.Producer do
  @moduledoc """
  Implementation of `Ming.Message.Producer` for the in-memory gateway.

  Publishes `%Ming.Message{}` structs to `Ming.Gateway.InMemory.Broker` so
  that in-memory consumers can receive them.
  """

  alias Ming.Message
  alias Ming.Gateway.InMemory
  alias Ming.Gateway.InMemory.Broker

  @behaviour Ming.Message.Producer

  @doc """
  Publishes one or more `%Ming.Message{}` structs to the in-memory broker.

  Options must include `:gateway` and `:publication`. The gateway value
  should be the keyword list passed to the gateway configuration, from
  which the broker name is derived.
  """
  @impl Ming.Message.Producer
  def publish(messages, opts) when is_list(messages),
    do: Enum.map(messages, &publish(&1, opts))

  def publish(%Message{} = message, opts) do
    gateway = Keyword.fetch!(opts, :gateway)
    publication = Keyword.fetch!(opts, :publication)

    broker_name =
      gateway
      |> Keyword.fetch!(:name)
      |> InMemory.broker_name()

    routing_key = Keyword.fetch!(publication, :routing_key)

    message =
      %Message{
        message
        | routing_key: routing_key,
          headers: Map.put(message.headers, :in_memory_gateway, Keyword.fetch!(gateway, :name))
      }

    Broker.publish(broker_name, routing_key, message)
  end
end
