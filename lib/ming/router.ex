defmodule Ming.Router do
  @moduledoc """
  Macro-based router for request registration and dispatch.

  A router maps one or more routing keys to handlers and middleware, then
  generates `send/3` and `publish/3` functions for runtime execution.
  """

  @doc """
  Injects router registration macros and default options.
  """
  defmacro __using__(opts) do
    metadata = Keyword.get(opts, :metadata, %{}) |> Macro.escape()
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

  @doc """
  Registers a middleware module to run for this router.
  """
  defmacro middleware(middleware) do
    quote generated: true do
      @registered_middlewares unquote(middleware)
    end
  end

  @doc """
  Registers one or many routing keys with handler options.
  """
  defmacro register(routing_key_or_keys, opts) do
    for routing_key <- List.wrap(routing_key_or_keys) do
      quote generated: true do
        @registered {
          unquote(routing_key),
          Keyword.merge(@default_opts, unquote(opts))
        }
      end
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    registered = Module.get_attribute(env.module, :registered) || []
    register_routing_keys = Enum.map(registered, &elem(&1, 0)) |> Enum.uniq()
    register_by_routing_key = Enum.group_by(registered, &elem(&1, 0), &elem(&1, 1))

    send_clauses =
      for {routing_key, opts_list} <- register_by_routing_key do
        if Enum.count(opts_list) == 1 do
          current_opts = Enum.at(opts_list, 0)

          quote do
            defp do_send(unquote(routing_key), command, opts) do
              do_dispatcher(
                unquote(routing_key),
                command,
                unquote(Macro.escape(current_opts)),
                opts
              )
            end
          end
        else
          quote do
            defp do_send(unquote(routing_key), _command, _opts),
              do: {:error, :more_than_one_handler_found}
          end
        end
      end

    publish_clauses =
      for {routing_key, opts_list} <- register_by_routing_key do
        if Enum.count(opts_list) == 1 do
          current_opts = Enum.at(opts_list, 0)

          quote do
            defp do_publish(unquote(routing_key), event, opts) do
              do_dispatcher(
                unquote(routing_key),
                event,
                unquote(Macro.escape(current_opts)),
                opts
              )
            end
          end
        else
          quote do
            defp do_publish(unquote(routing_key), event, opts) do
              all_opts = unquote(Macro.escape(opts_list))

              Enum.map(
                all_opts,
                &do_dispatcher(unquote(routing_key), event, &1, opts)
              )
            end
          end
        end
      end

    quote generated: true do
      @doc """
      Returns a list of all registered routing keys.
      """
      @spec __register_routing_keys__() :: [Ming.routing_key()]
      def __register_routing_keys__, do: unquote(register_routing_keys)

      @doc """
      Sends a command to the handler registered for the given `routing_key`.
      """
      @spec send(Ming.routing_key(), any(), keyword(Ming.send_opts())) :: Ming.resp()
      def send(routing_key, command, opts \\ []), do: do_send(routing_key, command, opts)

      unquote(send_clauses)
      defp do_send(_routing_key, _request, _opts), do: {:error, :unregistered_command}

      @doc """
      Publishes an event to all handlers registered for the given `routing_key`.
      """
      @spec publish(Ming.routing_key(), any(), keyword(Ming.publish_opts())) ::
              Ming.resp() | [Ming.resp()]
      def publish(routing_key, event, opts \\ []), do: do_publish(routing_key, event, opts)

      unquote(publish_clauses)
      defp do_publish(_routing_key, _request, _opts), do: {:error, :unregistered_command}

      defp do_dispatcher(routing_key, request, system_opts, user_opts) do
        alias Ming.Context
        alias Ming.Dispatcher

        handler = Keyword.fetch!(system_opts, :handler)
        middleware = Keyword.get(system_opts, :middleware, []) ++ @registered_middlewares

        opts = Keyword.merge(system_opts, user_opts)
        id = Keyword.get(opts, :id, UUIDv7.generate())
        correlation_id = Keyword.get(opts, :correlation_id, UUIDv7.generate())
        metadata = Keyword.get(opts, :metadata, %{})
        timeout = Keyword.get(opts, :timeout, :infinity)

        context = %Context{
          assigns: %{},
          id: id,
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

      defp resolve_routing_key(opts, request), do: Keyword.fetch!(opts, :routing_key)
    end
  end
end
