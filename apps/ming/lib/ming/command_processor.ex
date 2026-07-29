defmodule Ming.CommandProcessor do
  @moduledoc """
  Macro-based command processor that aggregates multiple routers and starts
  the messaging gateway supervision tree.

  A `Ming.CommandProcessor` module is both the command dispatch entry point
  and a supervisor. It builds routing tables at compile time, dispatches
  `send/2`, `publish/2` and `post/2` calls to the correct router, and starts
  the configured messaging gateways on startup.

  ## Example

      defmodule MyApp.CommandProcessor do
        use Ming.CommandProcessor, otp_app: :my_app

        router(MyApp.Router)
      end

  Then add it to your supervision tree:

      children = [
        MyApp.CommandProcessor
      ]

  And configure the gateways:

      config :my_app, MyApp.CommandProcessor,
        gateways: [
          [
            adapter: Ming.Gateway.AMQP,
            name: :my_amqp,
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

  @doc """
  Injects router aggregation macros and command processor options.
  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)

    default_message_mapper =
      Keyword.get(opts, :default_message_mapper, Ming.Message.Mapper.Json)

    quote do
      use Supervisor

      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      @otp_app unquote(otp_app)
      @default_message_mapper unquote(default_message_mapper)

      Module.register_attribute(__MODULE__, :routers, accumulate: true)

      @routers Ming.Message.Router

      @doc false
      def __ming_otp_app__, do: @otp_app

      @doc """
      Starts the command processor supervisor linked to the current process.

      The processor name is registered under `__MODULE__` by default.
      A custom name can be provided with the `:name` option.
      """
      @spec start_link(keyword()) :: Supervisor.on_start()
      def start_link(opts \\ []) do
        name = Keyword.get(opts, :name, __MODULE__)
        Supervisor.start_link(__MODULE__, opts, name: name)
      end

      @impl true
      def init(opts) do
        otp_app =
          if Keyword.has_key?(opts, :otp_app) do
            Keyword.fetch!(opts, :otp_app)
          else
            @otp_app
          end

        gateways =
          otp_app
          |> Application.get_env(__MODULE__, [])
          |> Keyword.get(:gateways, [])
          |> Enum.map(&Keyword.put(&1, :command_processor, __MODULE__))

        Supervisor.init([{Ming.Gateway.Supervisor, gateways}], strategy: :one_for_one)
      end
    end
  end

  @doc """
  Registers a router and all its routing keys into the command processor.
  """
  defmacro router(router_ast) do
    router = Macro.expand(router_ast, __CALLER__)

    for routing_key <- router.__register_routing_keys__() do
      quote generated: true do
        @routers {unquote(routing_key), unquote(router)}
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    routers =
      env.module
      |> Module.get_attribute(:routers)
      |> List.wrap()
      |> Enum.flat_map(fn
        {_routing_key, _router} = entry -> [entry]
        router when is_atom(router) -> Enum.map(router.__register_routing_keys__(), &{&1, router})
      end)

    routing_key_by_module = Enum.group_by(routers, &elem(&1, 0), &elem(&1, 1))

    send_clauses =
      for {routing_key, routers_list} <- routing_key_by_module do
        if Enum.count(routers_list) == 1 do
          router = Enum.at(routers_list, 0)

          quote do
            defp do_send(unquote(routing_key), command, opts),
              do: unquote(router).send(unquote(routing_key), command, opts)
          end
        else
          quote do
            defp do_send(unquote(routing_key), _command, _opts),
              do: {:error, :more_than_one_handler_found}
          end
        end
      end

    publish_clauses =
      for {routing_key, routers_list} <- routing_key_by_module do
        if Enum.count(routers_list) == 1 do
          router = Enum.at(routers_list, 0)

          quote do
            defp do_publish(unquote(routing_key), event, opts),
              do: unquote(router).publish(unquote(routing_key), event, opts)
          end
        else
          quote do
            defp do_publish(unquote(routing_key), event, opts),
              do:
                execute_dispatch_strategy(
                  Keyword.get(opts, :dispatch_strategy, :sequential),
                  unquote(routers_list),
                  unquote(routing_key),
                  event,
                  opts
                )
          end
        end
      end

    quote generated: true do
      @doc """
      Routes a command to the corresponding router for execution.
      """
      @spec send(any(), keyword(Ming.send_opts()) | Ming.routing_key()) :: Ming.resp()
      def send(command, opts \\ [])

      def send(command, routing_key) when is_atom(routing_key),
        do: do_send(routing_key, command, [])

      def send(command, opts) when is_list(opts) do
        routing_key = resolve_routing_key(opts, command)
        do_send(routing_key, command, opts)
      end

      unquote(send_clauses)
      defp do_send(_routing_key, _request, _opts), do: {:error, :unregistered_command}

      @doc """
      Routes an event to all corresponding routers for execution.
      """
      @spec publish(any(), keyword(Ming.publish_opts()) | Ming.routing_key()) ::
              Ming.resp() | [Ming.resp()]
      def publish(event, opts \\ [])

      def publish(event, routing_key) when is_atom(routing_key),
        do: do_publish(routing_key, event, [])

      def publish(event, opts) when is_list(opts) do
        routing_key = resolve_routing_key(opts, event)
        do_publish(routing_key, event, opts)
      end

      unquote(publish_clauses)
      defp do_publish(_routing_key, _request, _opts), do: {:error, :unregistered_command}

      @doc """
      Publishes a request through the configured messaging gateway.

      Accepts either a routing key atom or a keyword list of options. When a
      keyword list is given, `:routing_key` is resolved from the request struct
      unless already provided.
      """
      @spec post(any(), keyword(Ming.send_opts()) | Ming.routing_key()) :: Ming.resp()
      def post(request, opts \\ [])

      def post(request, routing_key) when is_atom(routing_key) do
        do_post(request, routing_key: routing_key)
      end

      def post(request, opts) when is_list(opts) do
        opts = Keyword.put_new(opts, :routing_key, resolve_routing_key(opts, request))
        do_post(request, opts)
      end

      defp do_post(request, opts) do
        metadata =
          Keyword.get(opts, :metadata, %{})
          |> Map.put(:message_routing_key, Keyword.fetch!(opts, :routing_key))
          |> Map.put(:default_message_mapper, @default_message_mapper)
          |> Map.put(:ming_application, __MODULE__)

        opts =
          opts
          |> Keyword.put(:metadata, metadata)
          |> Keyword.put(:routing_key, :ming_produce_message)

        __MODULE__.send(request, opts)
      end

      defp resolve_routing_key(opts, request) when is_struct(request),
        do: Keyword.get(opts, :routing_key, request.__struct__)

      defp resolve_routing_key(opts, _request), do: Keyword.fetch!(opts, :routing_key)

      defp extract_stream_resp({:ok, res}), do: res
      defp extract_stream_resp({:exit, reason}), do: {:error, reason}

      defp execute_dispatch_strategy(:sequential, routers, routing_key, event, opts),
        do: Enum.map(routers, & &1.publish(routing_key, event, opts))

      defp execute_dispatch_strategy(:parallel, routers, routing_key, event, opts),
        do:
          Task.async_stream(routers, & &1.publish(routing_key, event, opts))
          |> Stream.map(&extract_stream_resp(&1))
          |> Enum.to_list()

      defp execute_dispatch_strategy({:parallel, async_opts}, routers, routing_key, event, opts),
        do:
          Task.async_stream(routers, & &1.publish(routing_key, event, opts), async_opts)
          |> Stream.map(&extract_stream_resp(&1))
          |> Enum.to_list()
    end
  end
end
