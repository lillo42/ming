defmodule Ming.Gateway.InMemory do
  @moduledoc """
  In-memory gateway adapter for local development and testing.

  Implements `Ming.Gateway` without external infrastructure. Messages are
  routed directly between publishers and subscribers inside the BEAM using
  `Registry` and `DynamicSupervisor`.

  ## Example configuration

      [
        adapter: Ming.Gateway.InMemory,
        name: :my_in_memory_gateway,
        publications: [
          [routing_key: :order_created]
        ],
        subscriptions: [
          [name: :orders, routing_key: :order_created]
        ]
      ]

  The `:command_processor` option is injected automatically by
  `Ming.Application`. It is only required when subscriptions are configured.
  Publications may be published directly via `Ming.Gateway.InMemory.Producer`.
  """

  use Supervisor

  alias Ming.Gateway.InMemory.Broker
  alias Ming.Gateway.InMemory.Consumer

  @typedoc """
  In-memory gateway configuration.
  """
  @type t :: keyword()

  @doc """
  Starts the in-memory gateway supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(args) do
    name = Keyword.get(args, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    name = Keyword.get(args, :name, __MODULE__)
    registry_name = registry_name(name)
    broker_name = broker_name(name)

    children =
      [
        {Registry, keys: :duplicate, name: registry_name},
        {Broker, name: broker_name, registry: registry_name}
      ]
      |> Enum.reverse()
      |> add_consumers(
        name,
        Keyword.get(args, :command_processor),
        Keyword.get(args, :subscriptions, [])
      )
      |> Enum.reverse()

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp add_consumers(children, _gateway_name, nil, []), do: children

  defp add_consumers(_children, _gateway_name, nil, [_subscription | _]) do
    raise ArgumentError,
          "InMemory gateway requires :command_processor when subscriptions are configured"
  end

  defp add_consumers(children, gateway_name, command_processor, subscriptions) do
    Enum.reduce(subscriptions, children, fn subscription, acc ->
      consumer_name = Keyword.fetch!(subscription, :name)
      routing_key = Keyword.fetch!(subscription, :routing_key)

      consumer_args = [
        name: consumer_name,
        gateway_name: gateway_name,
        routing_key: routing_key,
        command_processor: command_processor,
        subscription: subscription
      ]

      [{Consumer, consumer_args} | acc]
    end)
  end

  @doc false
  def registry_name(gateway_name), do: :"#{gateway_name}_registry"

  @doc false
  def broker_name(gateway_name), do: :"#{gateway_name}_broker"

  @behaviour Ming.Gateway

  @impl Ming.Gateway
  def producer, do: Ming.Gateway.InMemory.Producer

  @doc """
  No-op provisioning for the in-memory adapter.
  """
  @impl Ming.Gateway
  def provision_infrastructure(_args), do: :ok
end
