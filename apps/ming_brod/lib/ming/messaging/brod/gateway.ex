defmodule Ming.Messaging.Brod.Gateway do
  @moduledoc """
  Kafka (brod) messaging gateway.

  Starts one `:brod` client (named after the gateway) and, per
  subscription, a `Ming.Messaging.Brod.Buffer`, a
  `:brod_group_subscriber_v2` that feeds it, and one
  `Ming.Messaging.Brod.Consumer` per subscription consumer that drains
  the buffer into the matching `Ming.Messaging.Processor` started by the
  dispatcher. See `Ming.Messaging.Brod` for the configuration options
  and delivery semantics.

  ## Topic provisioning

  The `:provisioner` option on a publication or subscription controls how
  its topic is provisioned at startup:

    * `:create` (default) — the topic is created if missing
      (`:num_partitions`, `:replication_factor` and `:topic_configs`
      apply; already-existing topics are left untouched, since Kafka
      topics cannot be reconfigured through creation)
    * `:validate` — startup fails with `{:error, {:topic_not_found, topic}}`
      unless the topic exists
    * `:assume` — the topic is left untouched

  When several entries resolve to the same topic, the strongest
  provisioner wins (`:create` > `:validate` > `:assume`). Provisioning
  uses the gateway's `:conn_config` and `:provision_timeout` (default
  10s) options.

  `start_link/1` raises `ArgumentError` when the configuration is
  malformed:

    * missing or empty `:endpoints`
    * a non-atom gateway `:name` (it names the `:brod` client)
    * an entry without `:topic` and `:routing_key`
    * an invalid `:provisioner`
    * a subscription `:buffer_size` that is not a positive integer
  """
  use Supervisor

  @behaviour Ming.Messaging.Gateway

  alias Ming.Messaging.Brod
  alias Ming.Messaging.Brod.Buffer
  alias Ming.Messaging.Brod.Consumer

  @provisioner_rank %{assume: 0, validate: 1, create: 2}

  def start_link(config) do
    validate!(config)

    case provision(config) do
      :ok -> Supervisor.start_link(__MODULE__, config, name: config.name)
      {:error, _reason} = error -> error
    end
  end

  @impl Ming.Messaging.Gateway
  def producer(_publication), do: Ming.Messaging.Brod.Producer

  @impl Ming.Messaging.Gateway
  def consumer(_subscription), do: Ming.Messaging.Brod.Consumer

  @impl true
  def init(config) do
    client_name = config.name

    registry = {Registry, keys: :unique, name: Brod.registry_name(client_name)}

    client = %{
      id: :brod_client,
      start:
        {:brod, :start_link_client,
         [Map.fetch!(config, :endpoints), client_name, Map.get(config, :client_config, [])]}
    }

    subscription_children =
      config
      |> Map.get(:subscriptions, [])
      |> Enum.flat_map(&subscription_children(config, &1, client_name))

    Supervisor.init([registry, client | subscription_children], strategy: :rest_for_one)
  end

  defp subscription_children(config, subscription, client_name) do
    subscription = Map.put(subscription, :gateway_name, config.name)
    buffer_name = Brod.buffer_name(subscription)

    buffer = %{
      id: {Buffer, buffer_name},
      start: {Buffer, :start_link, [[name: buffer_name]]}
    }

    subscriber = %{
      id: {:brod_group_subscriber, buffer_name},
      start:
        {:brod_group_subscriber_v2, :start_link,
         [subscriber_config(config, subscription, client_name, buffer_name)]}
    }

    [buffer, subscriber] ++ consumer_children(config, subscription, buffer_name)
  end

  defp consumer_children(config, subscription, buffer_name) do
    count = Map.get(subscription, :number_of_consumers, 1)
    indices = if is_integer(count) and count >= 1, do: 1..count, else: []

    for index <- indices do
      consumer_name = Brod.consumer_name(subscription, index)

      processor_name =
        Ming.Messaging.Processor.child_name(config.name, subscription[:name], index)

      %{
        id: {:consumer, consumer_name},
        start:
          {Consumer, :start_link,
           [
             [
               name: consumer_name,
               buffer: buffer_name,
               processor: processor_name,
               subscription: subscription
             ]
           ]}
      }
    end
  end

  defp subscriber_config(_config, subscription, client_name, buffer_name) do
    topic = Brod.topic(subscription)

    %{
      client: client_name,
      group_id: Map.get(subscription, :group_id) || "ming-#{client_name}-#{topic}",
      topics: [topic],
      cb_module: Ming.Messaging.Brod.Subscriber,
      message_type: :message,
      init_data: %{buffer: buffer_name, routing_key: Map.fetch!(subscription, :routing_key)},
      group_config: Map.get(subscription, :group_config, []),
      consumer_config: Map.get(subscription, :consumer_config, [])
    }
  end

  defp validate!(config) do
    validate_name!(config)
    validate_endpoints!(config)

    Enum.each(entries(config), fn entry ->
      validate_topic_resolvable!(config, entry)
      validate_provisioner!(config, entry)
    end)

    Enum.each(Map.get(config, :subscriptions, []), &validate_buffer_size!(config, &1))
  end

  defp entries(config) do
    Map.get(config, :publications, []) ++ Map.get(config, :subscriptions, [])
  end

  defp provision(config) do
    config
    |> entries()
    |> Enum.group_by(&Brod.topic/1)
    |> Enum.reduce_while(:ok, fn {topic, topic_entries}, :ok ->
      entry = Enum.max_by(topic_entries, &provisioner_rank/1)

      case provision_topic(config, topic, entry) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp provisioner(entry), do: Map.get(entry, :provisioner, :create)

  defp provisioner_rank(entry), do: Map.fetch!(@provisioner_rank, provisioner(entry))

  defp provision_topic(config, topic, entry) do
    case provisioner(entry) do
      :assume ->
        :ok

      :validate ->
        case topic_exists?(config, topic) do
          true -> :ok
          false -> {:error, {:topic_not_found, topic}}
          {:error, _reason} = error -> error
        end

      :create ->
        case create_topic(config, entry) do
          :ok -> :ok
          {:error, :topic_already_exists} -> :ok
          {:error, _reason} = error -> error
        end
    end
  end

  defp create_topic(config, entry) do
    :brod.create_topics(
      Map.fetch!(config, :endpoints),
      [topic_config(entry)],
      %{timeout: provision_timeout(config)},
      conn_config(config)
    )
  end

  defp topic_exists?(config, topic) do
    case :brod.get_metadata(Map.fetch!(config, :endpoints), [topic], conn_config(config)) do
      {:ok, metadata} ->
        metadata
        |> Map.get(:topics, [])
        |> Enum.any?(fn topic_metadata ->
          Map.get(topic_metadata, :name) == topic and
            Map.get(topic_metadata, :error_code, :no_error) == :no_error
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp topic_config(entry) do
    %{
      name: Brod.topic(entry),
      num_partitions: Map.get(entry, :num_partitions, -1),
      replication_factor: Map.get(entry, :replication_factor, -1),
      assignments: [],
      configs:
        Enum.map(Map.get(entry, :topic_configs, []), fn {name, value} ->
          %{name: to_string(name), value: to_string(value)}
        end)
    }
  end

  defp conn_config(config), do: Map.get(config, :conn_config, [])

  defp provision_timeout(config), do: Map.get(config, :provision_timeout, 10_000)

  defp validate_name!(config) do
    unless is_atom(config.name) do
      raise ArgumentError,
            "gateway #{inspect(config.name)} expects an atom :name, got: #{inspect(config.name)}"
    end
  end

  defp validate_endpoints!(config) do
    case Map.get(config, :endpoints) do
      endpoints when is_list(endpoints) and endpoints != [] ->
        :ok

      endpoints ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} expects a non-empty list of :endpoints, " <>
                "got: #{inspect(endpoints)}"
    end
  end

  defp validate_provisioner!(config, entry) do
    case provisioner(entry) do
      provisioner when is_map_key(@provisioner_rank, provisioner) ->
        :ok

      provisioner ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} expects :provisioner to be one of " <>
                "#{inspect(Map.keys(@provisioner_rank))}, got: #{inspect(provisioner)}"
    end
  end

  defp validate_topic_resolvable!(config, subscription) do
    case Map.get(subscription, :topic) || Map.get(subscription, :routing_key) do
      nil ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} has a subscription without :topic or " <>
                ":routing_key: #{inspect(subscription)}"

      "" ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} has a subscription with an empty topic: " <>
                inspect(subscription)

      _topic ->
        :ok
    end
  end

  defp validate_buffer_size!(config, subscription) do
    case Map.get(subscription, :buffer_size, 1) do
      size when is_integer(size) and size >= 1 ->
        :ok

      size ->
        raise ArgumentError,
              "gateway #{inspect(config.name)} expects :buffer_size to be a positive integer, " <>
                "got: #{inspect(size)}"
    end
  end
end
