defmodule Ming.Gateway.Brod do
  @moduledoc """
  Kafka gateway supervisor that manages a `:brod` client and group subscribers.

  This module implements the `Ming.Gateway` behaviour and starts a supervision tree
  with the following children:
  - a single `:brod` client
  - one `:brod_group_subscriber_v2` per configured subscription

  ## Example configuration

      [
        adapter: Ming.Gateway.Brod,
        name: :my_kafka,
        connection: [
          endpoints: [{"localhost", 9092}]
        ],
        publications: [
          [routing_key: :order_created, topic_or_queue: "orders"]
        ],
        subscriptions: [
          [
            name: :orders,
            topic_or_queue: "orders",
            routing_key: :order_created,
            group_id: "my-consumer-group"
          ]
        ]
      ]

  ## Subscription options

  - `:name` (required) — unique subscription name.
  - `:topic_or_queue` (required) — Kafka topic to consume from.
  - `:routing_key` (required) — Ming routing key set on consumed messages.
  - `:group_id` — Kafka consumer group id, defaults to the subscription name.
  - `:processing_timeout` — timeout passed to the command processor,
    defaults to `:infinity`.
  - `:consumer_config` — extra `:brod` consumer config, defaults to `[]`.
  - `:group_config` — extra `:brod` group config, defaults to `[]`.
  - `:requeue_routing_key` — routing key of a publication the message is
    republished to when the handler requeues it (Kafka has no native requeue).
  - `:dead_letter_queue_routing_key` — routing key of a publication the
    message is forwarded to when the handler rejects it (Kafka has no
    native reject).
  - `:invalid_message_routing_key` — routing key of a publication an
    unacceptable message (one that fails to decode) is forwarded to;
    falls back to `:dead_letter_queue_routing_key` when not configured.
  """

  use Supervisor

  alias Ming.Gateway.Brod.Consumer

  @doc """
  Starts the Kafka gateway supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: Keyword.get(args, :name, __MODULE__))
  end

  @impl true
  def init(args) do
    name = Keyword.get(args, :name, __MODULE__)
    client = client_name(name)

    connection = Keyword.fetch!(args, :connection)
    endpoints = Keyword.fetch!(connection, :endpoints)

    client_config =
      connection
      |> Keyword.delete(:endpoints)
      |> Keyword.put_new(:auto_start_producers, true)

    children =
      [
        %{
          id: client,
          type: :worker,
          restart: :permanent,
          start: {:brod, :start_link_client, [endpoints, client, client_config]}
        }
      ]
      |> add_subscriptions(
        client,
        Keyword.get(args, :command_processor),
        Keyword.get(args, :subscriptions, [])
      )

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the `:brod` client name used for a given gateway name.
  """
  @spec client_name(atom() | String.t()) :: atom()
  def client_name(name), do: :"#{name}_client"

  defp add_subscriptions(acc, _gateway_name, nil, []), do: acc

  defp add_subscriptions(_acc, _gateway_name, nil, [_subscription | _]) do
    raise ArgumentError,
          "Kafka gateway requires :command_processor when subscriptions are configured"
  end

  defp add_subscriptions(acc, _gateway_name, _command_processor, []), do: acc

  defp add_subscriptions(acc, gateway_name, command_processor, [subscription | next]) do
    name = Keyword.fetch!(subscription, :name)
    topic = subscription |> Keyword.fetch!(:topic_or_queue) |> to_string()

    init_data = [
      routing_key: Keyword.fetch!(subscription, :routing_key),
      command_processor: command_processor,
      timeout: Keyword.get(subscription, :processing_timeout, :infinity),
      requeue_routing_key: Keyword.get(subscription, :requeue_routing_key),
      dead_letter_queue_routing_key: Keyword.get(subscription, :dead_letter_queue_routing_key),
      invalid_message_routing_key: Keyword.get(subscription, :invalid_message_routing_key)
    ]

    config = %{
      client: gateway_name,
      group_id: Keyword.get(subscription, :group_id, to_string(name)),
      topics: [topic],
      cb_module: Consumer,
      message_type: :message_set,
      init_data: init_data,
      consumer_config: Keyword.get(subscription, :consumer_config, []),
      group_config: Keyword.get(subscription, :group_config, [])
    }

    child = %{
      id: name,
      type: :worker,
      restart: :permanent,
      start: {:brod, :start_link_group_subscriber_v2, [config]}
    }

    [child | add_subscriptions(acc, gateway_name, command_processor, next)]
  end

  @behaviour Ming.Gateway

  @impl Ming.Gateway
  def producer, do: Ming.Gateway.Brod.Producer

  @doc """
  Provisions Kafka infrastructure (topics) before the gateway starts.

  This is called by `Ming.Gateway.Supervisor` during startup.

  Topics are taken from the `:topic_or_queue` of each publication and
  subscription. The `:provision` option controls the behaviour:

  - `:assume` (default) — does nothing, assumes the topic already exists.
  - `:validate` — checks the topic exists, returns `{:error, reason}` otherwise.
  - `:create` or `{:create, opts}` — creates the topic; `opts` accepts
    `:num_partitions` (default 1), `:replication_factor` (default 1) and
    `:configs` (extra topic configs).
  """
  @impl Ming.Gateway
  def provision_infrastructure(args) do
    endpoints =
      args
      |> Keyword.fetch!(:connection)
      |> Keyword.fetch!(:endpoints)

    topics = Keyword.get(args, :publications, []) ++ Keyword.get(args, :subscriptions, [])

    ensure_topics_exists(endpoints, topics)
  end

  defp ensure_topics_exists(endpoints, configs) do
    Enum.reduce_while(configs, :ok, fn config, :ok ->
      topic = Keyword.get(config, :topic_or_queue)
      provision = Keyword.get(config, :provision, :assume)

      case ensure_topic_exists(endpoints, topic, provision) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_topic_exists(_endpoints, nil, _provision), do: :ok
  defp ensure_topic_exists(_endpoints, _topic, :assume), do: :ok

  defp ensure_topic_exists(endpoints, topic, :validate) do
    case fetch_metadata(endpoints, to_string(topic)) do
      {:ok, _metadata} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_topic_exists(endpoints, topic, provision) do
    opts =
      case provision do
        :create -> []
        {:create, opts} -> opts
      end

    topic_config = %{
      name: to_string(topic),
      num_partitions: Keyword.get(opts, :num_partitions, 1),
      replication_factor: Keyword.get(opts, :replication_factor, 1),
      assignments: [],
      configs: Keyword.get(opts, :configs, [])
    }

    case create_topic(endpoints, topic_config) do
      :ok -> :ok
      {:error, reason} -> if already_exists?(reason), do: :ok, else: {:error, reason}
    end
  end

  # brod throws errors instead of returning {:error, reason}
  defp fetch_metadata(endpoints, topic) do
    :brod.get_metadata(endpoints, [topic])
  catch
    :throw, reason -> {:error, reason}
  end

  defp create_topic(endpoints, topic_config) do
    :brod.create_topics(endpoints, [topic_config], %{timeout: 10_000})
  catch
    :throw, reason -> {:error, reason}
  end

  defp already_exists?(:topic_already_exists), do: true

  # Apache Kafka reports "already exists" while Redpanda reports
  # "has already been created"
  defp already_exists?(reason) when is_binary(reason),
    do: reason =~ "already exists" or reason =~ "already been created"

  defp already_exists?(_reason), do: false
end
