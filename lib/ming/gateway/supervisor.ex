defmodule Ming.Gateway.Supervisor do
  @moduledoc """
  Supervisor that starts all configured messaging gateways.

  Before starting each gateway, its adapter's `provision_infrastructure/1`
  callback is invoked to create exchanges, queues, and bindings.

  ## Example

      children = [
        {Ming.Gateway.Supervisor, [
          [
            adapter: Ming.Gateway.AMQP,
            name: :my_gateway,
            command_processor: MyApp.CommandProcessor,
            connection: [uri: "amqp://guest:guest@localhost"],
            exchange: [name: "events", type: :topic],
            publications: [
              [routing_key: :order_created, number_of_performers: 2]
            ],
            subscriptions: [
              [name: :orders, topic_or_queue: "orders.queue", routing_key: :order_created]
            ]
          ]
        ]}
      ]
  """

  use Supervisor

  @doc """
  Starts the gateway supervisor linked to the current process.

  When called without arguments, the supervisor reads gateway configurations
  from `Application.get_env(:ming, :gateways, [])`.
  """
  @spec start_link() :: Supervisor.on_start()
  @spec start_link([keyword()]) :: Supervisor.on_start()
  def start_link(opts \\ nil)

  def start_link(nil) do
    start_link(Application.get_env(:ming, :gateways, []))
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    case validate(init_arg) do
      :ok ->
        Supervisor.init(create_children(init_arg), strategy: :one_for_one)

      reply ->
        reply
    end
  end

  defp validate(args) do
    publications =
      args
      |> Enum.flat_map(&Keyword.get(&1, :publications, []))
      |> Enum.group_by(&Keyword.fetch!(&1, :routing_key))
      |> Map.to_list()

    subscriptions =
      args
      |> Enum.flat_map(&Keyword.get(&1, :subscriptions, []))
      |> Enum.group_by(&Keyword.fetch!(&1, :name))
      |> Map.to_list()

    with :ok <- validate_publication(publications),
         :ok <- validate_subscription(subscriptions) do
      :ok
    else
      reply ->
        reply
    end
  end

  defp validate_publication([]), do: :ok

  defp validate_publication([{key, publications} | next]) when is_atom(key) do
    case Enum.count(publications) do
      total when total > 1 ->
        {:error, {:duplicate_publication_routing_key, key}}

      _ ->
        validate_publication(next)
    end
  end

  defp validate_publication([{key, _publications} | _next]) do
    {:error, {:invalid_publication_routing_key, key}}
  end

  defp validate_subscription([]), do: :ok

  defp validate_subscription([{key, subscription} | next]) when is_atom(key) do
    case Enum.count(subscription) do
      total when total > 1 ->
        {:error, {:duplicate_subscription_name, key}}

      _ ->
        validate_subscription(next)
    end
  end

  defp validate_subscription([{key, _subscription} | _next]) do
    {:error, {:invalid_subscription_name, key}}
  end

  defp create_children([]), do: []

  defp create_children([current | next]) do
    acc = create_children(next)

    adapter = Keyword.fetch!(current, :adapter)

    case adapter.provision_infrastructure(current) do
      :ok ->
        [{adapter, current} | acc]

      {:error, reason} ->
        raise "Failed to provision infrastructure for #{inspect(adapter)}: #{inspect(reason)}"
    end
  end
end
