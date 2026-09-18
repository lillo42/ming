defmodule Ming.Dispatcher do
  @doc false
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app, :ming)
    message_mapper = Keyword.get(opts, :message_mapper, Ming.Messaging.Mapper.Json)

    metadata = Keyword.get(opts, :metadata, %{}) |> Macro.escape()
    timeout = Keyword.get(opts, :timeout, :infinity)

    executing_strategy = Keyword.get(opts, :executing_strategy, Ming.ExecutingStrategy.Sequencial)

    quote generated: true do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      @otp_app unquote(otp_app)
      @message_mapper unquote(message_mapper)

      @executing_strategy unquote(executing_strategy)

      @default_opts [
        metadata: unquote(metadata),
        timeout: unquote(timeout)
      ]

      Module.register_attribute(__MODULE__, :routing_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :middlewares, accumulate: true)
    end
  end

  defmacro middleware(middleware, opts \\ []) do
    quote generated: true do
      @middlewares {unquote(middleware), unquote(opts)}
    end
  end

  defmacro routing_key(routing_key, opts) do
    handlers = Keyword.get(opts, :handler) || Keyword.get(opts, :handlers, [])
    handlers = List.wrap(handlers)

    if Enum.empty?(handlers) do
      quote generated: true do
        @routing_keys {
          unquote(routing_key),
          Keyword.merge(@default_opts, unquote(opts))
        }
      end
    else
      middlewares = Keyword.get(opts, :middlewares, [])

      for handler <- List.wrap(handlers) do
        tmp = [{Ming.Middleware.CallHandler, args: handler, order: 1000} | middlewares]

        quote generated: true do
          @routing_keys {
            unquote(routing_key),
            @default_opts
            |> Keyword.merge(unquote(opts))
            |> Keyword.put(:middleware, unquote(tmp))
          }
        end
      end
    end
  end

  defmacro router(router_ast) do
    router = Macro.expand(router_ast, __CALLER__)

    for routing_key <- router.__routing_keys__() do
      quote generated: true do
        @routing_keys unquote(routing_key)
      end
    end
  end

  defmacro __before_compile__(_envs) do
    quote generated: true do
      @final_routing_keys Enum.group_by(@routing_keys, &elem(&1, 0))
                          |> Enum.map(fn {key, opts} ->
                            opts =
                              if Enum.empty?(@middlewares) do
                                opts
                              else
                                Enum.map(opts, fn item ->
                                  middlewares = Keyword.get(items, :middlewares, [])

                                  Keyword.put(
                                    items,
                                    :middlewares,
                                    middlewares ++ @middlewares
                                  )
                                end)
                              end

                            opts =
                              Enum.map(opts, fn item ->
                                middlewares =
                                  Keyword.get(items, :middlewares, [])
                                  |> Enum.sort(
                                    &(Keyword.get(&2, :order, 0) >= Keyword.get(&1, :order, 0))
                                  )

                                Keyword.put(items, :middlewares, middlewares)
                              end)

                            {key, opts}
                          end)

      defp executing_strategy(:sequencial), do: {Ming.ExecutingStrategy.Sequencial, []}
      defp executing_strategy(:parallel), do: {Ming.ExecutingStrategy.Parallel, []}
      defp executing_strategy(other), do: other

      for {routing_key, middlewares} <- @final_routing_keys do
        @routing_key routing_key
        @pipelines Enum.map(middlewares, %Ming.Pipeline{middlewares: middlewares})
        @pipelines_counter Enum.count(@pipelines)

        defp do_dispatcher(@routing_key, :send, opts) do
          if @pipelines_counter > 1 do
            {:error, :more_than_one_pipeline_found}
          else
            middlewares = Keyword.get(opts, :middlewares, [])

            do_dispatcher(
              @routing_key,
              Ming.Pipeline.concat(@pipelines, middlewares),
              :send,
              opts
            )
          end
        end

        defp do_dispatcher(@routing_key, operation, opts) do
          middlewares = Keyword.get(opts, :middlewares, [])

          do_dispatcher(
            @routing_key,
            Ming.Pipeline.concat(@pipelines, middlewares),
            operation,
            opts
          )
        end
      end

      defp do_dispatcher(routing_key, pipelines, operation, opts) do
        request = Keyword.fetch!(opts, :request)

        context = %Ming.Context{
          id: Keyword.get(opts, :id, UUIDv7.generate()),
          correlation_id: Keyword.get(opts, :id, UUIDv7.generate()),
          metadata: Keyword.get(opts, :metadata, %{}),
          request: request,
          routing_key: routing_key,
          timeout: Keyword.get(opts, :timeout, 5000),
          timestamp: Keyword.get(opts, :timestamp, DateTime.utc_now())
        }

        {executing_strategy, args} =
          Keyword.get(opts, :executing_strategy, @executing_strategy)
          |> executing_strategy()

        executing_strategy.execute(context, @pipelines, args)
      end

      defp request_to_routing_key(request) when is_struct(request) do
        request.__struct__
      end

      defp request_to_routing_key(request) when is_atom(request) or is_binary(request) do
        request
      end

      defp request_to_routing_key(request), do: raise("")

      defp resolve_routing_key(request, opts) do
        Keyword.get(opts, :routing_key) || request_to_routing_key(request)
      end

      def send(command, opts_or_timeout \\ [])

      def send(command, timeout) when is_integer(timeout), do: send(commad, timeout: timeout)

      def send(command, :infinity), do: send(commad, timeout: :infinity)

      def send(command, opts) do
        do_dispatcher(
          resolve_routing_key(commad),
          :send,
          Keyword.put(opts, :request, command)
        )
      end

      def publish(event, opts_or_timeout \\ [])

      def publish(event, timeout) when is_integer(timeout), do: publish(event, timeout: timeout)

      def publish(event, :infinity), do: publish(event, timeout: :infinity)

      def publish(event, opts) do
        do_dispatcher(
          resolve_routing_key(event),
          :publish,
          Keyword.put(opts, :request, event)
        )
      end
    end
  end
end
