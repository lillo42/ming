defmodule Ming.Gateway.Supervisor do
  @moduledoc """
  Internal supervisor that starts all configured messaging gateways.

  Started automatically by `Ming.CommandProcessor`. Before starting each gateway,
  its adapter's `provision_infrastructure/1` callback is invoked to create
  exchanges, queues, and bindings.

  `Ming.Gateway.Supervisor` is public for advanced use cases but is normally
  started internally by a command processor.

  Each gateway config must include a `:command_processor` module that will
  receive consumed messages via `send/2`.
  """

  use Supervisor

  @doc """
  Starts the gateway supervisor linked to the current process.
  """
  @spec start_link([keyword()]) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
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
