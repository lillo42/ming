defmodule Ming.Dispatcher do
  @moduledoc """
  Compiles routing keys into dispatch functions.

  A dispatcher declares routing keys directly and/or imports them from a
  `Ming.Router`, then generates `send/2` and `publish/2`:

      defmodule MyApp.Dispatcher do
        use Ming.Dispatcher

        router MyApp.Router

        routing_key "reports.generate", handler: MyApp.GenerateReportHandler
      end

  `send/2` requires exactly one handler for the key and returns its
  response; `publish/2` runs every handler's pipeline and returns a list of
  responses. The routing key defaults to the request struct module and can
  be overridden with the `:routing_key` option.

  `post/2` encodes the request with the publication's mapper and produces
  it through the gateway that declares a publication for the routing key.

  ## Supervision

  A dispatcher is also a `Supervisor`: adding it to an application
  supervision tree starts one child per declared gateway adapter plus one
  `Ming.Messaging.Pumper` per subscription:

      children = [
        MyApp.Dispatcher
      ]

  A subscription may set `:number_of_consumers` (default `1`) to start
  that many competing consumers — one pumper each — polling its queue.

  Gateway adapters must therefore implement `start_link/1` (or
  `child_spec/1`) accepting their configuration map — which includes the
  gateway `:name` — in addition to the `Ming.Messaging.Gateway` behaviour.
  """

  @doc false
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)

    metadata = Keyword.get(opts, :metadata, Macro.escape(%{}))
    timeout = Keyword.get(opts, :timeout, :infinity)
    execution_strategy = Keyword.get(opts, :execution_strategy, Ming.ExecutionStrategy.Sequential)

    mapper = Keyword.get(opts, :mapper, :json)
    batch_processing = Keyword.get(opts, :batch_processing, :sequential)

    quote generated: true do
      # Dispatchers define their own send/2.
      import Kernel, except: [send: 2]
      import Ming.Registration
      import Ming.Dispatcher, only: [router: 1, gateway: 3, transformer: 1, transformer: 2]

      use Supervisor

      @before_compile Ming.Dispatcher

      @otp_app unquote(otp_app)

      Module.register_attribute(__MODULE__, :routing_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :middlewares, accumulate: true)
      Module.register_attribute(__MODULE__, :gateways, accumulate: true)
      Module.register_attribute(__MODULE__, :transformers, accumulate: true)

      @default_opts [
        metadata: unquote(metadata),
        timeout: unquote(timeout)
      ]

      @batch_processing unquote(batch_processing)
      @execution_strategy unquote(execution_strategy)
      @mapper unquote(mapper)

      # Internal pipeline backing post/2: encodes the request into a
      # %Ming.Messaging.Message{} and produces it through the gateway.
      routing_key(:ming_post_message,
        handler: Ming.Messaging.ProduceHandler,
        middlewares: [
          {Ming.Messaging.Middleware.Encode, [order: 0]}
        ]
      )

      transformer(Ming.Messaging.Transformer.ApplyDefaults)
      transformer(Ming.Messaging.Transformer.StructureCloudEvent)

      @doc """
      Resolves the publication for the given routing key from the merged
      gateway configuration. Returns `nil` when no publication matches.
      """
      def resolve_publication(routing_key) do
        Enum.find_value(config()[:gateways], fn {_name, gateway} ->
          Enum.find(gateway[:publications] || [], &(&1.routing_key == routing_key))
        end)
      end

      defoverridable resolve_publication: 1

      @doc """
      Returns the dispatcher configuration: the compile-time defaults merged
      with the application environment (`config @otp_app, __MODULE__, ...`).
      """
      def config do
        defaults = [
          gateways: __gateways__(),
          mapper: @mapper,
          timeout: @default_opts[:timeout]
        ]

        app_env = Application.get_env(@otp_app, __MODULE__, [])
        Ming.Dispatcher.Config.merge(defaults, app_env)
      end

      defoverridable config: 0

      @doc """
      Starts the dispatcher's supervision tree: one child per declared
      gateway adapter and one `Ming.Messaging.Pumper` per subscription.
      """
      def start_link(opts \\ []) do
        Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
      end

      @impl true
      def init(_opts) do
        children =
          config()
          |> Keyword.get(:gateways, [])
          |> Enum.flat_map(&gateway_children/1)

        Supervisor.init(children, strategy: :one_for_one)
      end

      defp gateway_children({name, gateway}) do
        adapter =
          Map.get(gateway, :adapter) ||
            raise ArgumentError, "gateway #{inspect(name)} does not declare an :adapter"

        gateway_config =
          gateway
          |> Map.delete(:adapter)
          |> Map.put(:name, name)

        pumpers =
          gateway
          |> Map.get(:subscriptions, [])
          |> Enum.flat_map(fn subscription ->
            consumer = adapter.consumer(subscription)

            for index <- 1..number_of_consumers(name, subscription) do
              Supervisor.child_spec(
                {Ming.Messaging.Pumper,
                 consumer: consumer, subscription: subscription, dispatcher: __MODULE__},
                id: {Ming.Messaging.Pumper, name, subscription[:name], index}
              )
            end
          end)

        [Supervisor.child_spec({adapter, gateway_config}, id: {adapter, name}) | pumpers]
      end

      defp number_of_consumers(gateway_name, subscription) do
        case Map.get(subscription, :number_of_consumers, 1) do
          count when is_integer(count) and count >= 1 ->
            count

          count ->
            raise ArgumentError,
                  "subscription #{inspect(subscription[:name])} of gateway " <>
                    "#{inspect(gateway_name)} expects :number_of_consumers to be a " <>
                    "positive integer, got: #{inspect(count)}"
        end
      end
    end
  end

  @doc """
  Imports every routing key declared in the given `Ming.Router` module.
  """
  defmacro router(router_ast) do
    router = Macro.expand(router_ast, __CALLER__)

    for {routing_key, opts} <- router.__routing_keys__() do
      quote generated: true do
        @routing_keys {unquote(routing_key), unquote(Macro.escape(opts))}
      end
    end
  end

  @doc """
  Declares a dispatcher-level transformer, merged into every gateway
  publication and subscription and sorted by the `:order` option
  (default `1`).
  """
  defmacro transformer(transformer, opts \\ []) do
    quote generated: true do
      @transformers {unquote(transformer), unquote(opts)}
    end
  end

  @doc """
  Declares a gateway with the given name and adapter.

  Publications and subscriptions inherit the dispatcher's `:mapper` and
  `:batch_processing` defaults unless overridden per gateway or per entry.
  The same gateway can be overridden at runtime through the application
  environment (see the `config/0` function generated on the dispatcher).
  """
  defmacro gateway(name, adapter, opts) do
    quote generated: true do
      opts = unquote(opts)

      mapper = Keyword.get(opts, :mapper, @mapper)
      batch_processing = Keyword.get(opts, :batch_processing, @batch_processing)

      config =
        opts
        |> Map.new()
        |> Map.put(:adapter, unquote(adapter))
        |> Map.update(:publications, [], fn pubs ->
          Enum.map(pubs, fn pub ->
            pub
            |> Map.new()
            |> Map.put(:gateway_name, unquote(name))
            |> Map.put_new(:mapper, mapper)
          end)
        end)
        |> Map.update(:subscriptions, [], fn subs ->
          Enum.map(subs, fn sub ->
            sub
            |> Map.new()
            |> Map.put(:gateway_name, unquote(name))
            |> Map.put_new(:batch_processing, batch_processing)
            |> Map.put_new(:mapper, mapper)
          end)
        end)

      @gateways {unquote(name), config}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    routing_keys = env.module |> Module.get_attribute(:routing_keys) |> Enum.reverse()
    middlewares = env.module |> Module.get_attribute(:middlewares) |> Enum.reverse()

    env.module
    |> Module.get_attribute(:gateways)
    |> validate_unique_publications!()

    grouped =
      routing_keys
      |> Enum.map(fn {key, opts} ->
        {key, Keyword.update(opts, :middlewares, middlewares, &(middlewares ++ &1))}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    clauses =
      for {routing_key, opts_list} <- grouped do
        pipelines =
          Enum.map(opts_list, fn opts ->
            Ming.Pipeline.concat(
              %Ming.Pipeline{middlewares: []},
              Keyword.get(opts, :middlewares, [])
            )
          end)

        key_opts = opts_list |> List.first() |> Keyword.drop([:middlewares])

        quote generated: true do
          defp do_dispatch(unquote(routing_key), :send, opts) do
            case unquote(Macro.escape(pipelines)) do
              [pipeline] ->
                [response] =
                  run_pipelines(
                    unquote(routing_key),
                    [pipeline],
                    unquote(Macro.escape(key_opts)),
                    opts
                  )

                response

              _pipelines ->
                {:error, :more_than_one_handler_found}
            end
          end

          defp do_dispatch(unquote(routing_key), :publish, opts) do
            run_pipelines(
              unquote(routing_key),
              unquote(Macro.escape(pipelines)),
              unquote(Macro.escape(key_opts)),
              opts
            )
          end

          defp do_dispatch(unquote(routing_key), :post, opts) do
            case unquote(Macro.escape(pipelines)) do
              [pipeline] ->
                [response] =
                  run_pipelines(
                    unquote(routing_key),
                    [pipeline],
                    unquote(Macro.escape(key_opts)),
                    opts
                  )

                response

              _pipelines ->
                {:error, :more_than_one_handler_found}
            end
          end
        end
      end

    quote generated: true do
      unquote(clauses)

      defp do_dispatch(_routing_key, _operation, _opts), do: {:error, :unregistered_routing_key}

      defp run_pipelines(routing_key, pipelines, key_opts, opts) do
        opts = @default_opts |> Keyword.merge(key_opts) |> Keyword.merge(opts)

        context = %Ming.Context{
          id: Keyword.get(opts, :id, UUIDv7.generate()),
          correlation_id: Keyword.get(opts, :correlation_id, UUIDv7.generate()),
          metadata: Keyword.get(opts, :metadata, %{}),
          request: Keyword.fetch!(opts, :request),
          routing_key: routing_key,
          timeout: Keyword.get(opts, :timeout, :infinity),
          timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
        }

        extra_middlewares = Keyword.get(opts, :middlewares, [])

        {strategy, args} =
          opts
          |> Keyword.get(:execution_strategy, @execution_strategy)
          |> resolve_strategy()

        pipelines
        |> Enum.map(&Ming.Pipeline.concat(&1, extra_middlewares))
        |> strategy.execute(context, args)
        |> Enum.map(&Ming.Context.response/1)
      end

      defp resolve_strategy(:sequential), do: {Ming.ExecutionStrategy.Sequential, []}
      defp resolve_strategy(:parallel), do: {Ming.ExecutionStrategy.Parallel, []}
      defp resolve_strategy({module, args}), do: {module, args}
      defp resolve_strategy(module) when is_atom(module), do: {module, []}

      defp infer_routing_key(request) when is_struct(request), do: request.__struct__

      defp infer_routing_key(request) when is_atom(request) or is_binary(request),
        do: request

      defp infer_routing_key(request) do
        raise ArgumentError,
              "cannot infer a routing key from #{inspect(request)}, " <>
                "use a struct or pass the :routing_key option"
      end

      defp resolve_routing_key(request, opts) do
        Keyword.get(opts, :routing_key) || infer_routing_key(request)
      end

      @doc """
      Sends a command to the single handler registered for its routing key.
      """
      @spec send(any(), timeout() | Ming.dispatch_opts()) :: Ming.resp()
      def send(command, opts_or_timeout \\ [])

      def send(command, timeout) when is_integer(timeout), do: do_send(command, timeout: timeout)
      def send(command, :infinity), do: do_send(command, timeout: :infinity)
      def send(command, opts) when is_list(opts), do: do_send(command, opts)

      defp do_send(command, opts) do
        do_dispatch(
          resolve_routing_key(command, opts),
          :send,
          Keyword.put(opts, :request, command)
        )
      end

      @doc """
      Publishes an event to every handler registered for its routing key.
      """
      @spec publish(any(), timeout() | Ming.dispatch_opts()) :: [Ming.resp()]
      def publish(event, opts_or_timeout \\ [])

      def publish(event, timeout) when is_integer(timeout),
        do: do_publish(event, timeout: timeout)

      def publish(event, :infinity), do: do_publish(event, timeout: :infinity)
      def publish(event, opts) when is_list(opts), do: do_publish(event, opts)

      defp do_publish(event, opts) do
        do_dispatch(
          resolve_routing_key(event, opts),
          :publish,
          Keyword.put(opts, :request, event)
        )
      end

      @doc """
      Posts a request to the publication registered for its routing key.
      """
      @spec post(any(), timeout() | Ming.dispatch_opts()) :: Ming.resp()
      def post(request, opts_or_timeout \\ [])

      def post(request, timeout) when is_integer(timeout), do: do_post(request, timeout: timeout)
      def post(request, :infinity), do: do_post(request, timeout: :infinity)
      def post(request, opts) when is_list(opts), do: do_post(request, opts)

      defp do_post(request, opts) do
        routing_key = resolve_routing_key(request, opts)

        case resolve_publication(routing_key) do
          nil ->
            {:error, :publication_not_found}

          publication ->
            metadata =
              opts
              |> Keyword.get(:metadata, %{})
              |> Map.put(:ming_mapper, publication[:mapper] || @mapper)
              |> Map.put(:ming_routing_key, routing_key)
              |> Map.put(:ming_publication, publication)
              |> Map.put(:ming_dispatcher, __MODULE__)

            do_dispatch(
              :ming_post_message,
              :post,
              opts
              |> Keyword.put(:request, request)
              |> Keyword.put(:metadata, metadata)
            )
        end
      end

      @doc """
      Returns the compile-time resolved gateway configuration, without
      application environment overrides. Use `config/0` for the merged view.
      """
      def __gateways__ do
        Ming.Dispatcher.resolve_gateways(
          Enum.reverse(@gateways),
          @mapper,
          Enum.reverse(@transformers)
        )
      end
    end
  end

  @doc false
  def resolve_gateways(gateways, mapper, transformers) do
    Enum.map(gateways, fn {name, config} ->
      {name,
       config
       |> Map.update(:publications, [], fn pubs ->
         Enum.map(pubs, &resolve_gateway_entry(&1, name, mapper, transformers))
       end)
       |> Map.update(:subscriptions, [], fn subs ->
         Enum.map(subs, &resolve_gateway_entry(&1, name, mapper, transformers))
       end)}
    end)
  end

  defp resolve_gateway_entry(entry, name, mapper, transformers) do
    merged =
      Enum.sort_by(
        Map.get(entry, :transformers, []) ++ transformers,
        fn {_module, opts} -> Keyword.get(opts, :order, 1) end
      )

    entry
    |> Map.put_new(:gateway_name, name)
    |> Map.put_new(:mapper, mapper)
    |> Map.put(:transformers, merged)
  end

  defp validate_unique_publications!(gateways) do
    gateways
    |> Enum.flat_map(fn {gateway_name, config} ->
      Enum.map(Map.get(config, :publications, []), &{&1.routing_key, gateway_name})
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.each(fn
      {_routing_key, [_gateway]} ->
        :ok

      {routing_key, gateway_names} ->
        raise ArgumentError,
              "duplicated publication routing key #{inspect(routing_key)} " <>
                "declared in gateways: #{inspect(Enum.uniq(gateway_names))}"
    end)
  end
end
