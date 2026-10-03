defmodule Ming.Messaging.InMemory.Gateway do
  @moduledoc """
  In-memory messaging gateway.

  Routes messages through `Ming.Messaging.InMemory.Queue` processes inside
  the BEAM, with no external broker. Useful for local development and
  tests.

  Publications and subscriptions resolve their queue from the `:queue`
  option, defaulting to their `:routing_key`. A publication and a
  subscription resolving to the same queue share it, so several
  subscriptions on the same queue compete for messages. Queue names are
  registered locally; string names are converted to atoms.

  The `:provisioner` option controls queue startup:

    * `:create` (default) — the queue is started under this gateway
    * `:validate` — startup fails with `{:error, {:queue_not_found, queue}}`
      unless another entry of this gateway creates the queue
    * `:assume` — the queue is left untouched (useful when another gateway
      in the same VM already creates it)

  Delivery is at-most-once: messages are removed from the queue when
  polled, so a crash between polling and processing loses them, and nacked
  messages are discarded.

  ## Configuration validation

  `start_link/1` raises `ArgumentError` when an entry is malformed:

    * a publication or subscription without `:queue` and `:routing_key`
      (its queue cannot be resolved)
    * an empty (`""`) or `nil` queue/routing key
    * a subscription `:buffer_size` that is not a positive integer

  A subscription may set `:number_of_consumers` (default `1`) to run
  several competing consumers on its queue (see `Ming.Dispatcher`).
  """
  use Supervisor

  @behaviour Ming.Messaging.Gateway

  alias Ming.Messaging.InMemory.Queue

  def start_link(config) do
    validate_entries!(config)

    case validate(config) do
      :ok -> Supervisor.start_link(__MODULE__, config, name: config.name)
      {:error, _reason} = error -> error
    end
  end

  @impl Ming.Messaging.Gateway
  def producer(_publication), do: Ming.Messaging.InMemory.Producer

  @impl Ming.Messaging.Gateway
  def consumer(_subscription), do: Ming.Messaging.InMemory.Consumer

  @impl true
  def init(config) do
    queues =
      config
      |> entries()
      |> Enum.filter(&(provisioner(&1) == :create))
      |> Enum.map(&queue_name/1)
      |> Enum.uniq()
      |> Enum.map(fn queue ->
        Supervisor.child_spec({Queue, [name: Queue.resolve_name(queue)]}, id: {Queue, queue})
      end)

    Supervisor.init(queues, strategy: :one_for_one)
  end

  defp entries(config) do
    Map.get(config, :publications, []) ++ Map.get(config, :subscriptions, [])
  end

  defp provisioner(entry), do: Map.get(entry, :provisioner, :create)

  defp queue_name(entry), do: Map.get(entry, :queue) || Map.fetch!(entry, :routing_key)

  defp validate_entries!(config) do
    Enum.each(entries(config), fn entry ->
      validate_queue_resolvable!(config, entry)
      validate_buffer_size!(config, entry)
    end)
  end

  defp validate_queue_resolvable!(config, entry) do
    case Map.get(entry, :queue) || Map.get(entry, :routing_key) do
      nil ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} has an entry without :queue or :routing_key: " <>
                inspect(entry)

      "" ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} has an entry with an empty queue name: " <>
                inspect(entry)

      _name ->
        :ok
    end
  end

  defp validate_buffer_size!(config, entry) do
    case Map.get(entry, :buffer_size, 1) do
      size when is_integer(size) and size >= 1 ->
        :ok

      size ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} expects :buffer_size to be a positive integer, " <>
                "got: #{inspect(size)}"
    end
  end

  defp validate(config) do
    created =
      for entry <- entries(config), provisioner(entry) == :create, into: MapSet.new() do
        queue_name(entry)
      end

    config
    |> entries()
    |> Enum.filter(&(provisioner(&1) == :validate))
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      queue = queue_name(entry)

      if MapSet.member?(created, queue) do
        {:cont, :ok}
      else
        {:halt, {:error, {:queue_not_found, queue}}}
      end
    end)
  end
end
