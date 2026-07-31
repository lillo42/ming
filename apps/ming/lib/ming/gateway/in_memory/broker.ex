defmodule Ming.Gateway.InMemory.Broker do
  @moduledoc """
  Pub/sub broker for the in-memory gateway.

  Maintains an ETS table that maps routing keys to subscriber pids and
  keeps a bounded message history per routing key. When a message is
  published, every subscriber currently registered for the routing key
  receives a copy.
  """

  use GenServer

  alias Ming.Message

  @default_history_limit 1_000

  @doc """
  Starts the broker linked to the current process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Publishes a message to all subscribers of `routing_key`.
  """
  @spec publish(atom(), atom(), Message.t()) :: :ok
  def publish(broker_name, routing_key, %Message{} = message) do
    GenServer.call(broker_name, {:publish, routing_key, message})
  end

  @doc """
  Subscribes the calling process to messages for a routing key.

  Optional `replay` argument controls whether stored history should be
  delivered to the new subscriber.
  """
  @spec subscribe(atom(), atom(), boolean()) :: :ok | {:error, any()}
  def subscribe(broker_name, routing_key, replay \\ false) do
    GenServer.call(broker_name, {:subscribe, routing_key, self(), replay})
  end

  @doc """
  Unsubscribes the calling process from a routing key.
  """
  @spec unsubscribe(atom(), atom()) :: :ok
  def unsubscribe(broker_name, routing_key) do
    GenServer.call(broker_name, {:unsubscribe, routing_key, self()})
  end

  @doc """
  Returns the last `limit` messages published to a routing key.
  """
  @spec history(atom(), atom(), non_neg_integer()) :: [Message.t()]
  def history(broker_name, routing_key, limit \\ @default_history_limit) do
    GenServer.call(broker_name, {:history, routing_key, limit})
  end

  @doc """
  Returns the configured history limit.
  """
  @spec history_limit(GenServer.server()) :: non_neg_integer()
  def history_limit(broker_name) do
    GenServer.call(broker_name, :history_limit)
  end

  @impl true
  def init(opts) do
    registry = Keyword.fetch!(opts, :registry)
    history_limit = Keyword.get(opts, :history_limit, @default_history_limit)

    table = :ets.new(:in_memory_broker, [:protected, :bag, read_concurrency: true])

    {:ok, %{registry: registry, table: table, history_limit: history_limit}}
  end

  @impl true
  def handle_call({:publish, routing_key, message}, _from, state) do
    store_message(state, routing_key, message)
    broadcast(state.registry, routing_key, message)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:subscribe, routing_key, pid, replay}, _from, state) do
    Registry.register(state.registry, routing_key, pid)

    if replay do
      messages = lookup_messages(state.table, routing_key)
      Enum.each(messages, &send(pid, {:in_memory_message, routing_key, &1}))
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unsubscribe, routing_key, pid}, _from, state) do
    Registry.unregister_match(state.registry, routing_key, pid)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:history, routing_key, limit}, _from, state) do
    messages =
      lookup_messages(state.table, routing_key)
      |> Enum.take(-limit)

    {:reply, messages, state}
  end

  @impl true
  def handle_call(:history_limit, _from, state) do
    {:reply, state.history_limit, state}
  end

  defp store_message(state, routing_key, message) do
    true = :ets.insert(state.table, {routing_key, message})

    prune_messages(state.table, routing_key, state.history_limit)
  end

  defp prune_messages(table, routing_key, limit) do
    messages = lookup_messages(table, routing_key)
    total = length(messages)

    if total > limit do
      to_drop = total - limit

      messages
      |> Enum.take(to_drop)
      |> Enum.each(&:ets.delete_object(table, {routing_key, &1}))
    end
  end

  defp lookup_messages(table, routing_key) do
    :ets.lookup(table, routing_key)
    |> Enum.map(&elem(&1, 1))
  end

  defp broadcast(registry, routing_key, message) do
    Registry.dispatch(registry, routing_key, fn entries ->
      Enum.each(entries, fn {_owner, pid} ->
        send(pid, {:in_memory_message, routing_key, message})
      end)
    end)
  end
end
