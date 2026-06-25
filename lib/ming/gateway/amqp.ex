if Code.ensure_loaded?(AMQP) do
  defmodule Ming.Gateway.AMQP do
    @moduledoc """
    AMQP gateway supervisor that manages connections, publishers, and consumers.

    This module implements the `Ming.Gateway` behaviour and starts a supervision tree
    with the following children:
    - a single `Ming.Gateway.AMQP.Connection`
    - one `NimblePool` per configured publication (for publishing)
    - one `Ming.Gateway.AMQP.Consumer` and one `NimblePool` per configured subscription

    ## Example configuration

        [
          adapter: Ming.Gateway.AMQP,
          name: :my_amqp,
          config: [
            connection: [uri: "amqp://guest:guest@localhost"],
            exchange: [name: "events", type: :topic],
            publications: [
              [routing_key: :order_created, number_of_performers: 2]
            ],
            subscriptions: [
              [name: :orders, topic_or_queue: "orders.queue", routing_key: :order_created]
            ]
          ]
        ]
    """

    use Supervisor

    alias AMQP.Channel
    alias AMQP.Exchange
    alias AMQP.Queue

    alias Ming.Gateway.AMQP.Connection
    alias Ming.Gateway.AMQP.Consumer
    alias Ming.Gateway.AMQP.MessageProcess
    alias Ming.Gateway.AMQP.Publisher

    @typedoc """Options for connecting to an AMQP broker."""
    @type connection ::
            {:uri, String.t() | URI.t() | nil}
            | {:username, String.t() | nil}
            | {:password, String.t() | nil}
            | {:virtual_host, String.t() | nil}
            | {:host, String.t() | nil}
            | {:port, non_neg_integer() | nil}
            | {:channel_max, non_neg_integer() | nil}
            | {:frame_max, non_neg_integer() | nil}
            | {:heartbeat, non_neg_integer() | nil}
            | {:connection_timeout, non_neg_integer() | nil}
            | {:ssl_options, any() | nil}
            | {:client_properties, any() | nil}
            | {:socket_options, any() | nil}
            | {:auth_mechanisms, any() | nil}
            | {:name, String.t() | nil}

    @typedoc """Supported AMQP exchange types."""
    @type exchange_type :: :direct | :fanout | :topic | :headers

    @doc """
    Starts the AMQP gateway supervisor.
    """
    @spec start_link(keyword()) :: Supervisor.on_start()
    def start_link(args) do
      Supervisor.start_link(__MODULE__, args, name: Keyword.get(args, :name, __MODULE__))
    end

    @impl true
    def init(args) do
      config = Keyword.fetch!(args, :config)
      name = Keyword.get(config, :name, __MODULE__)

      connection_config =
        config
        |> Keyword.fetch!(:connection)
        |> Keyword.put_new(:name, name)

      children =
        [{Connection, connection_config}]
        |> publication(name, Keyword.get(config, :publications, []))
        |> subscriptions(name, Keyword.fetch!(args, :command_process), Keyword.get(config, :subscriptions, []))

      Supervisor.init(children, strategy: :one_for_one)
    end

    defp publication(acc, _gateway_name, []), do: acc

    defp publication(acc, gateway_name, [publication | next]) do
      [
        {
          NimblePool,
          name: Keyword.fetch!(publication, :routing_key),
          pool_size: Keyword.get(publication, :number_of_performers, 1),
          lazy: Keyword.get(publication, :lazy, false),
          idle_timeout: Keyword.get(publication, :idle_timeout, :infinity),
          max_idle_pings: Keyword.get(publication, :idle_pings, :infinity),
          worker: {Publisher, Keyword.put(publication, :gateway_name, gateway_name)}
        }
        | publication(acc, gateway_name, next)
      ]
    end

    defp subscriptions(acc, _gateway_name, _command_process, []), do: acc

    defp subscriptions(acc, gateway_name, command_process, [subscription | next]) do
      [
        {Consumer, Keyword.put(subscription, :gateway_name, gateway_name)},
        {
          NimblePool,
          name: Keyword.fetch!(subscription, :name),
          pool_size: Keyword.get(subscription, :number_of_performers, 1),
          lazy: Keyword.get(subscription, :lazy, false),
          idle_timeout: Keyword.get(subscription, :idle_timeout, :infinity),
          max_idle_pings: Keyword.get(subscription, :idle_pings, :infinity),
          worker:
            {MessageProcess,
             subscription
             |> Keyword.put(:gateway_name, gateway_name)
             |> Keyword.put(:command_process, command_process)}
        }
        | subscriptions(acc, gateway_name, command_process, next)
      ]
    end

    @behaviour Ming.Gateway
    @doc """
    Provisions AMQP infrastructure (exchanges, queues, bindings) before the gateway starts.

    This is called by `Ming.Gateway.Supervisor` during startup.
    """
    @impl Ming.Gateway
    def provision_infrastructure(args) do
      config = Keyword.fetch!(args, :config)
      connection = Keyword.fetch!(config, :connection)

      exchange = Keyword.get(config, :exchange)
      exchange_name = if is_binary(exchange), do: exchange, else: Keyword.fetch!(exchange, :name)

      create_connection(connection)
      |> create_channel()
      |> ensure_exchange_exists(exchange)
      |> ensure_exchange_exists(Keyword.get(config, :dead_letter_exchange))
      |> ensure_queues_exists(Keyword.get(args, :subscriptions, []), exchange_name)
      |> close_channel()
      |> close_conn()
    end

    defp create_connection(uri_or_opts) do
      case AMQP.Connection.open(uri_or_opts) do
        {:ok, conn} ->
          {:ok, conn}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp create_channel({:ok, conn}) do
      case Channel.open(conn) do
        {:ok, channel} ->
          {:ok, conn, channel}

        {:error, reason} ->
          {:error, reason, conn, nil}
      end
    end

    defp create_channel(val), do: val

    defp ensure_exchange_exists(val, nil), do: val

    defp ensure_exchange_exists({:error, reason}, _exchange), do: {:error, reason}
    defp ensure_exchange_exists({:error, reason, conn}, _exchange), do: {:error, reason, conn}

    defp ensure_exchange_exists({:error, reason, conn, channel}, _exchange),
      do: {:error, reason, conn, channel}

    defp ensure_exchange_exists(val, exchange) when is_binary(exchange), do: val

    defp ensure_exchange_exists({:ok, conn, channel}, exchange) do
      case ensure_exchange_exists(Keyword.get(exchange, :provision), channel, exchange) do
        :ok ->
          {:ok, conn, channel}

        {:error, reason} ->
          {:error, reason, conn, channel}
      end
    end

    defp ensure_exchange_exists(:assume, _channel, _exchange), do: :ok

    defp ensure_exchange_exists(:validate, channel, exchange) do
      name = Keyword.fetch!(exchange, :name)
      type = Keyword.get(exchange, :type, :direct)

      Exchange.declare(channel, name, type, passive: true)
    end

    defp ensure_exchange_exists({:validate, opts}, channel, exchange) do
      name = Keyword.fetch!(exchange, :name)
      type = Keyword.get(exchange, :type, :direct)

      Exchange.declare(channel, name, type, Keyword.put(opts, :passive, true))
    end

    defp ensure_exchange_exists({_action, opts}, channel, exchange) do
      name = Keyword.fetch!(exchange, :name)
      type = Keyword.get(exchange, :type, :direct)

      Exchange.declare(channel, name, type, Keyword.put(opts, :passive, false))
    end

    defp ensure_exchange_exists(_action, channel, exchange) do
      name = Keyword.fetch!(exchange, :name)
      type = Keyword.get(exchange, :type, :direct)

      Exchange.declare(channel, name, type)
    end

    defp ensure_queues_exists(val, [], _exchange), do: val

    defp ensure_queues_exists({:error, reason}, _subscriptions, _exchange), do: {:error, reason}

    defp ensure_queues_exists({:error, reason, conn}, _subscriptions, _exchange),
      do: {:error, reason, conn}

    defp ensure_queues_exists({:error, reason, conn, channel}, _subscriptions, _exchange),
      do: {:error, reason, conn, channel}

    defp ensure_queues_exists({:ok, conn, channel}, [subscription | next], exchange) do
      queue = Keyword.fetch!(subscription, :topic_or_queue)
      dead_letter_queue = Keyword.get(subscription, :dead_letter)
      provision = Keyword.get(subscription, :provision, :assume)

      with {:ok, _queue} <- ensure_queue_exists(provision, channel, dead_letter_queue),
           {:ok, _queue} <- ensure_queue_exists(provision, channel, queue),
           :ok <- ensure_queue_is_bind(provision, channel, queue, exchange) do
        ensure_queues_exists({:ok, conn, channel}, next, exchange)
      else
        {:error, reason} ->
          {:error, reason, conn, channel}
      end
    end

    defp ensure_queue_exists(_action, _channel, nil), do: {:ok, nil}
    defp ensure_queue_exists(:assume, _channel, _queue), do: {:ok, nil}

    defp ensure_queue_exists(:validate, channel, queue) do
      Queue.declare(channel, queue, passive: true)
    end

    defp ensure_queue_exists({:validate, opts}, channel, queue) do
      Queue.declare(channel, queue, Keyword.put(opts, :passive, true))
    end

    defp ensure_queue_exists({_action, opts}, channel, queue) do
      Queue.declare(channel, queue, Keyword.put(opts, :passive, false))
    end

    defp ensure_queue_exists(_action, channel, queue) do
      Queue.declare(channel, queue, passive: false)
    end

    defp ensure_queue_is_bind(:assume, _channel, _queue, _exchange), do: :ok
    defp ensure_queue_is_bind(:validate, _channel, _queue, _exchange), do: :ok
    defp ensure_queue_is_bind({:validate, _opts}, _channel, _queue, _exchange), do: :ok

    defp ensure_queue_is_bind({_action, opts}, channel, queue, exchange) do
      Queue.bind(channel, queue, exchange, opts)
    end

    defp ensure_queue_is_bind(_action, channel, queue, exchange) do
      Queue.bind(channel, queue, exchange)
    end

    defp close_channel({:error, reason}), do: {:error, reason}
    defp close_channel({:error, reason, conn, nil}), do: {:error, reason, conn}

    defp close_channel({:error, reason, conn, channel}) do
      AMQP.Channel.close(channel)
      {:error, reason, conn}
    end

    defp close_channel({:ok, conn, channel}) do
      case Channel.close(channel) do
        :ok ->
          {:ok, conn}

        {:error, reason} ->
          {:error, reason, conn}
      end
    end

    defp close_conn({:error, reason}), do: {:error, reason}

    defp close_conn({:error, reason, conn}) do
      AMQP.Connection.close(conn)

      {:error, reason}
    end

    defp close_conn({:ok, conn}) do
      AMQP.Connection.close(conn)
    end
  end
end
