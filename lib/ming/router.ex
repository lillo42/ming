defmodule Ming.Router do
  defmacro __using__(opts) do
    metadata = Keyword.get(opts, :metadata, %{})
    timeout = Keyword.get(opts, :timeout, :infinity)

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :registered, accumulate: true)
      Module.register_attribute(__MODULE__, :registered_middlewares, accumulate: true)

      @default_opts [
        metadata: unquote(metadata),
        timeout: unquote(timeout)
      ]
    end
  end

  defmacro middleware(middleware) do
    quote generated: true do
      @registered_middlewares unquote(middleware)
    end
  end

  defmacro register(router_key_or_keys, opts) do
    for router_key <- List.wrap(router_key_or_keys) do
      quote generated: true do
        @registered {
          unquote(router_key),
          Keyword.merge(@default_opts, unquote(opts))
        }
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      @register_routing_keys @registered
                             |> Enum.map(&elem(&1, 0))
                             |> Enum.uniq()

      @register_by_routing_key Enum.group_by(@registered, &elem(&1, 0), &elem(&1, 1))

      def __register_routing_keys__, do: @register_routing_keys

      @doc false
      def send(routing_key, command, opts \\ []), do: do_send(routing_key, command, opts)

      for {routing_key, opts} <- @register_by_routing_key do
        @routing_key routing_key

        if Enum.count(opts) == 1 do
          @current_opts Enum.at(opts, 0)

          defp do_send(@routing_key, command, opts) do
            do_dispatcher(@routing_key, command, current_opts, opts)
          end
        else
          defp do_send(@routing_key, _command, _opts), do: {:error, :more_than_one_handler_found}
        end
      end

      defp do_send(_routing_key, _command, _opts), do: {:error, :unregistered_command}

      @doc false
      def publish(routing_key, event, opts \\ []), do: do_publish(router_key, event, opts)

      for {routing_key, opts} <- @register_by_routing_key do
        @routing_key routing_key

        if Enum.count(opts) == 1 do
          @current_opts Enum.at(opts, 0)

          defp do_publish(@routing_key, event, opts) do
            do_dispatcher(@routing_key, event, current_opts, opts)
          end
        else
          @all_opts opts

          defp do_publish(@routing_key, event, opts) do
            # I'm expecting only one per router

            Enum.map(
              @all_opts,
              &do_dispatcher(@routing_key, event, &1, opts)
            )
          end
        end
      end

      defp do_publish(_routing_key, _command, _opts), do: {:error, :unregistered_command}

      defp do_dispatcher(routing_key, request, system_opts, user_opts) do
        alias Ming.Context
        alias Ming.Dispatcher

        handler = Keyword.fetch!(system_opts, :handler)
        middleware = Keyword.get(system_opts, :middleware, [])

        opts = Keyword.merge(system_opts, user_opts)
        correlation_id = Keyword.get(opts, :correlation_id)
        metadata = Keyword.get(opts, :metadata, %{})
        timeout = Keyword.get(opts, :timeout, :infinity)

        context = %Context{
          assigns: %{},
          correlation_id: correlation_id,
          handler: handler,
          metadata: metadata,
          middlewares: middleware ++ [Ming.Middleware.CallHandler],
          request: request,
          routing_key: routing_key,
          timestamp: DateTime.utc_now(),
          timeout: timeout
        }

        Dispatcher.dispatch(context)
        |> Context.response()
      end

      defp resolve_routing_key(opts, request) when is_struct(request),
        do: Keyword.get(opts, :routing_key, request.__struct__)

      defp resolve_routing_key(opts, request), do: Keyword.fetch(opts, :routing_key)
    end
  end
end
