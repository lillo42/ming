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
          connection: [
            uri: "amqp://guest:guest@localhost",
            retry: [max_retries: 5, base_delay: 1_000]
          ],
          exchange: [
            name: "events",
            type: :topic,
            provision: :create
          ],
          publications: [
            [routing_key: :order_created, number_of_performers: 2]
          ],
          subscriptions: [
            [name: :orders, topic_or_queue: "orders.queue", routing_key: :order_created]
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

    @typedoc """
    Options for connecting to an AMQP broker.
    """
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

    @typedoc """
    Supported AMQP exchange types.
    """
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
      name = Keyword.get(args, :name, __MODULE__)
      connection_name = :"#{name}_connection"

      connection_config =
        args
        |> Keyword.fetch!(:connection)
        |> Keyword.put_new(:name, connection_name)
        |> Keyword.put_new(:retry, [])

      children =
        [{Connection, [name: connection_name, connection: connection_config]}]
        |> add_publications(connection_name, Keyword.get(args, :publications, []))
        |> add_subscriptions(
          connection_name,
          Keyword.get(args, :command_processor),
          Keyword.get(args, :subscriptions, [])
        )

      Supervisor.init(Enum.reverse(children), strategy: :one_for_one)
    end

    defp add_subscriptions(acc, _gateway_name, nil, []), do: acc

    defp add_subscriptions(_acc, _gateway_name, nil, [_subscription | _]) do
      raise ArgumentError,
            "AMQP gateway requires :command_processor when subscriptions are configured"
    end

    defp add_subscriptions(acc, _gateway_name, _command_process, []), do: acc

    defp add_subscriptions(acc, gateway_name, command_process, [subscription | next]) do
      consumer_name = Keyword.fetch!(subscription, :name)
      process_pool_name = :"#{consumer_name}_process"

      consumer_opts =
        subscription
        |> Keyword.put(:gateway_name, gateway_name)
        |> Keyword.put(:process_pool_name, process_pool_name)

      worker_opts =
        subscription
        |> Keyword.put(:gateway_name, gateway_name)
        |> Keyword.put(:command_process, command_process)

      pool_opts = [
        name: process_pool_name,
        pool_size: Keyword.get(subscription, :number_of_performers, 1),
        lazy: Keyword.get(subscription, :lazy, false),
        idle_timeout: Keyword.get(subscription, :idle_timeout, :infinity),
        max_idle_pings: Keyword.get(subscription, :idle_pings, :infinity),
        worker: {MessageProcess, worker_opts}
      ]

      [
        %{id: consumer_name, start: {Consumer, :start_link, [consumer_opts]}},
        %{id: {process_pool_name, MessageProcess}, start: {NimblePool, :start_link, [pool_opts]}}
        | add_subscriptions(acc, gateway_name, command_process, next)
      ]
    end

    defp add_publications(acc, _gateway_name, []), do: acc

    defp add_publications(acc, gateway_name, [publication | next]) do
      pool_name = Keyword.fetch!(publication, :routing_key)

      worker_opts =
        publication
        |> Keyword.put(:gateway_name, gateway_name)
        |> Keyword.put_new(:retry, [])

      pool_opts = [
        name: pool_name,
        pool_size: Keyword.get(publication, :number_of_performers, 1),
        lazy: Keyword.get(publication, :lazy, false),
        idle_timeout: Keyword.get(publication, :idle_timeout, :infinity),
        max_idle_pings: Keyword.get(publication, :idle_pings, :infinity),
        worker: {Publisher, worker_opts}
      ]

      [
        %{id: pool_name, start: {NimblePool, :start_link, [pool_opts]}}
        | add_publications(acc, gateway_name, next)
      ]
    end

    @behaviour Ming.Gateway

    @impl Ming.Gateway
    def producer, do: Ming.Gateway.AMQP.Producer

    @doc """
    Provisions AMQP infrastructure (exchanges, queues, bindings) before the gateway starts.

    This is called by `Ming.Gateway.Supervisor` during startup.
    """
    @impl Ming.Gateway
    def provision_infrastructure(args) do
      connection = Keyword.fetch!(args, :connection)

      exchange = Keyword.get(args, :exchange)
      exchange_name = if is_binary(exchange), do: exchange, else: Keyword.fetch!(exchange, :name)

      dead_letter_exchange_name =
        dead_letter_exchange_name(Keyword.get(args, :dead_letter_exchange))

      create_connection(connection)
      |> create_channel()
      |> ensure_exchange_exists(exchange)
      |> ensure_exchange_exists(Keyword.get(args, :dead_letter_exchange))
      |> ensure_queues_exists(
        Keyword.get(args, :subscriptions, []),
        exchange_name,
        dead_letter_exchange_name
      )
      |> close_channel()
      |> close_conn()
    end

    defp dead_letter_exchange_name(nil), do: nil
    defp dead_letter_exchange_name(exchange) when is_binary(exchange), do: exchange
    defp dead_letter_exchange_name(exchange), do: Keyword.fetch!(exchange, :name)

    defp create_connection(uri_or_opts) do
      uri_or_opts =
        case Keyword.get(uri_or_opts, :uri) do
          uri when not is_nil(uri) -> uri
          _ -> uri_or_opts
        end

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

    defp ensure_exchange_exists({:error, reason, conn, nil}, _exchange),
      do: {:error, reason, conn, nil}

    defp ensure_exchange_exists({:error, reason, conn, channel}, _exchange),
      do: {:error, reason, conn, channel}

    defp ensure_exchange_exists(val, exchange) when is_binary(exchange), do: val

    defp ensure_exchange_exists({:ok, conn, channel}, exchange) do
      try do
        case ensure_exchange_exists(Keyword.get(exchange, :provision), channel, exchange) do
          :ok ->
            {:ok, conn, channel}

          {:error, reason} ->
            {:error, reason, conn, channel}
        end
      catch
        :exit, reason ->
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

    defp ensure_queues_exists(val, [], _exchange, _dead_letter_exchange), do: val

    defp ensure_queues_exists({:error, reason}, _subscriptions, _exchange, _dead_letter_exchange),
      do: {:error, reason}

    defp ensure_queues_exists(
           {:error, reason, conn, channel},
           _subscriptions,
           _exchange,
           _dead_letter_exchange
         ),
         do: {:error, reason, conn, channel}

    defp ensure_queues_exists({:ok, conn, channel}, [subscription | next], exchange, dlx) do
      queue = Keyword.fetch!(subscription, :topic_or_queue)
      routing_key = Keyword.fetch!(subscription, :routing_key)
      dead_letter_queue = Keyword.get(subscription, :dead_letter)
      provision = Keyword.get(subscription, :provision, :assume)

      # Broker-native dead lettering: the subscription queue is declared with
      # x-dead-letter-* arguments pointing at the gateway's dead letter
      # exchange, and the dead letter queue is bound to it
      queue_provision =
        if dlx && dead_letter_queue do
          with_dead_letter_arguments(provision, dlx, routing_key)
        else
          provision
        end

      try do
        with {:ok, _queue} <- ensure_queue_exists(provision, channel, dead_letter_queue),
             :ok <-
               ensure_dead_letter_is_bound(
                 dlx,
                 provision,
                 channel,
                 dead_letter_queue,
                 routing_key
               ),
             {:ok, _queue} <- ensure_queue_exists(queue_provision, channel, queue),
             :ok <- ensure_queue_is_bound(provision, channel, queue, exchange, subscription) do
          ensure_queues_exists({:ok, conn, channel}, next, exchange, dlx)
        else
          {:error, reason} ->
            {:error, reason, conn, channel}
        end
      catch
        :exit, reason ->
          {:error, reason, conn, channel}
      end
    end

    defp with_dead_letter_arguments({action, opts}, dlx, routing_key)
         when action in [:create, :create_or_override] do
      arguments = [
        {"x-dead-letter-exchange", :longstr, dlx},
        {"x-dead-letter-routing-key", :longstr, to_string(routing_key)}
      ]

      {action, Keyword.update(opts, :arguments, arguments, &(&1 ++ arguments))}
    end

    defp with_dead_letter_arguments(action, dlx, routing_key)
         when action in [:create, :create_or_override],
         do: with_dead_letter_arguments({action, []}, dlx, routing_key)

    defp with_dead_letter_arguments(provision, _dlx, _routing_key), do: provision

    defp ensure_dead_letter_is_bound(dlx, provision, channel, dead_letter_queue, routing_key) do
      if dlx && dead_letter_queue && provision_creates?(provision) do
        Queue.bind(channel, dead_letter_queue, dlx, routing_key: to_string(routing_key))
      else
        :ok
      end
    end

    defp provision_creates?(:create), do: true
    defp provision_creates?(:create_or_override), do: true

    defp provision_creates?({action, _opts}) when action in [:create, :create_or_override],
      do: true

    defp provision_creates?(_provision), do: false

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

    defp ensure_queue_is_bound(:assume, _channel, _queue, _exchange, _subscription), do: :ok
    defp ensure_queue_is_bound(:validate, _channel, _queue, _exchange, _subscription), do: :ok

    defp ensure_queue_is_bound({:validate, _opts}, _channel, _queue, _exchange, _subscription),
      do: :ok

    defp ensure_queue_is_bound({_action, _opts}, channel, queue, exchange, subscription),
      do: bind_queue(channel, queue, exchange, subscription)

    defp ensure_queue_is_bound(_action, channel, queue, exchange, subscription),
      do: bind_queue(channel, queue, exchange, subscription)

    defp bind_queue(channel, queue, exchange, subscription) do
      routing_key = subscription |> Keyword.fetch!(:routing_key) |> to_string()
      Queue.bind(channel, queue, exchange, routing_key: routing_key)
    end

    defp close_channel({:error, reason}), do: {:error, reason}
    defp close_channel({:error, reason, conn, nil}), do: {:error, reason, conn}

    defp close_channel({:error, reason, conn, channel}) do
      try do
        AMQP.Channel.close(channel)
      catch
        _, _ -> :ok
      end

      {:error, reason, conn}
    end

    defp close_channel({:ok, conn, channel}) do
      try do
        case Channel.close(channel) do
          :ok ->
            {:ok, conn}

          {:error, reason} ->
            {:error, reason, conn}
        end
      catch
        _, _ ->
          {:ok, conn}
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
