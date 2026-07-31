defmodule Ming.Gateway.KafkaEx do
  @moduledoc """
  Kafka gateway supervisor that manages a `KafkaEx` client and consumer groups.

  This module implements the `Ming.Gateway` behaviour and starts a supervision tree
  with the following children:
  - a single `KafkaEx` client
  - one `KafkaEx.Consumer.ConsumerGroup` per configured subscription

  ## Example configuration

      [
        adapter: Ming.Gateway.KafkaEx,
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
  - `:number_of_performer` — how many consumer groups are started for the
    subscription, defaults to `1`. Each one joins `:group_id` as an
    independent consumer group member, so the topic's partitions are split
    between them. Members beyond the partition count stay idle; raise
    `:num_partitions` (see below) to scale parallelism further.
  - `:processing_timeout` — timeout passed to the command processor,
    defaults to `:infinity`.
  - `:consumer_config` — extra `KafkaEx.Consumer.GenConsumer` options
    (e.g. `:auto_offset_reset`, `:commit_interval`, `:commit_threshold`),
    defaults to `[]`.
  - `:group_config` — extra `KafkaEx.Consumer.ConsumerGroup` options
    (e.g. `:heartbeat_interval`, `:session_timeout`), defaults to `[]`.
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

  alias Elixir.KafkaEx.API, as: KafkaExAPI
  alias Elixir.KafkaEx.Consumer.ConsumerGroup
  alias Elixir.KafkaEx.Messages.CreateTopics
  alias Ming.Gateway.KafkaEx.Consumer

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

    client_opts =
      connection
      |> Keyword.delete(:endpoints)
      |> Keyword.merge(
        name: client,
        brokers: endpoints,
        consumer_group: :no_consumer_group
      )

    children =
      [
        %{
          id: client,
          type: :worker,
          restart: :permanent,
          start: {KafkaExAPI, :start_client, [client_opts]}
        }
      ]
      |> add_subscriptions(
        endpoints,
        Keyword.get(args, :command_processor),
        Keyword.get(args, :subscriptions, [])
      )

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the `KafkaEx` client name used for a given gateway name.
  """
  @spec client_name(atom() | String.t()) :: atom()
  def client_name(name), do: :"#{name}_client"

  defp add_subscriptions(acc, _endpoints, nil, []), do: acc

  defp add_subscriptions(_acc, _endpoints, nil, [_subscription | _]) do
    raise ArgumentError,
          "Kafka gateway requires :command_processor when subscriptions are configured"
  end

  defp add_subscriptions(acc, _endpoints, _command_processor, []), do: acc

  defp add_subscriptions(acc, endpoints, command_processor, [subscription | next]) do
    name = Keyword.fetch!(subscription, :name)
    topic = subscription |> Keyword.fetch!(:topic_or_queue) |> to_string()
    performers = number_of_performers(subscription)

    init_data = %{
      routing_key: Keyword.fetch!(subscription, :routing_key),
      command_processor: command_processor,
      timeout: Keyword.get(subscription, :processing_timeout, :infinity),
      requeue_routing_key: Keyword.get(subscription, :requeue_routing_key),
      dead_letter_queue_routing_key: Keyword.get(subscription, :dead_letter_queue_routing_key),
      invalid_message_routing_key: Keyword.get(subscription, :invalid_message_routing_key)
    }

    consumer_group_opts =
      [uris: endpoints, extra_consumer_args: init_data]
      |> Keyword.merge(Keyword.get(subscription, :consumer_config, []))
      |> Keyword.merge(Keyword.get(subscription, :group_config, []))

    group_id = Keyword.get(subscription, :group_id, to_string(name))

    children =
      for index <- 1..performers do
        %{
          id: performer_id(name, index, performers),
          type: :supervisor,
          restart: :permanent,
          start: {ConsumerGroup, :start_link, [Consumer, group_id, [topic], consumer_group_opts]}
        }
      end

    children ++ add_subscriptions(acc, endpoints, command_processor, next)
  end

  defp number_of_performers(subscription) do
    case Keyword.get(subscription, :number_of_performer, 1) do
      performers when is_integer(performers) and performers >= 1 ->
        performers

      other ->
        raise ArgumentError,
              ":number_of_performer must be a positive integer, got: #{inspect(other)}"
    end
  end

  defp performer_id(name, _index, 1), do: name
  defp performer_id(name, index, _performers), do: {name, index}

  @behaviour Ming.Gateway

  @impl Ming.Gateway
  def producer, do: Ming.Gateway.KafkaEx.Producer

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

    topics =
      (Keyword.get(args, :publications, []) ++ Keyword.get(args, :subscriptions, []))
      |> Enum.reject(fn config ->
        is_nil(Keyword.get(config, :topic_or_queue)) or
          Keyword.get(config, :provision, :assume) == :assume
      end)

    if topics == [] do
      :ok
    else
      provision_topics(endpoints, topics)
    end
  end

  defp provision_topics(endpoints, topics) do
    case KafkaExAPI.start_client(brokers: endpoints, consumer_group: :no_consumer_group) do
      {:ok, client} ->
        try do
          ensure_topics_exists(client, topics)
        after
          GenServer.stop(client)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_topics_exists(client, configs) do
    Enum.reduce_while(configs, :ok, fn config, :ok ->
      topic = Keyword.get(config, :topic_or_queue)
      provision = Keyword.get(config, :provision, :assume)

      case ensure_topic_exists(client, topic, provision) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_topic_exists(_client, nil, _provision), do: :ok
  defp ensure_topic_exists(_client, _topic, :assume), do: :ok

  defp ensure_topic_exists(client, topic, :validate) do
    case KafkaExAPI.topics_metadata(client, [to_string(topic)]) do
      {:ok, [_topic | _]} -> :ok
      {:ok, []} -> {:error, :unknown_topic_or_partition}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_topic_exists(client, topic, provision) do
    opts =
      case provision do
        :create -> []
        {:create, opts} -> opts
      end

    config_entries =
      opts
      |> Keyword.get(:configs, [])
      |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)

    result =
      KafkaExAPI.create_topic(client, to_string(topic),
        num_partitions: Keyword.get(opts, :num_partitions, 1),
        replication_factor: Keyword.get(opts, :replication_factor, 1),
        config_entries: config_entries
      )

    case result do
      {:ok, %CreateTopics{} = created} ->
        case CreateTopics.failed_topics(created) do
          [] -> :ok
          [%{error: :topic_already_exists} | _] -> :ok
          [%{error: error} | _] -> {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
