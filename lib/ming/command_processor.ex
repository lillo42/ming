defmodule Ming.CommandProcessor do
  @moduledoc """
  Macro-based command processor that aggregates multiple routers.

  It builds routing tables at compile time and dispatches `send/2` and
  `publish/2` calls to the correct router module.
  """

  @doc """
  Injects router aggregation macros.
  """
  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :routers, accumulate: true)
    end
  end

  @doc """
  Registers a router and all its routing keys into the processor.
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
    routers = Module.get_attribute(env.module, :routers) || []
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
            defp do_send(unquote(routing_key), _request, _opts),
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
      @spec send(any(), keyword(Ming.send_opts()) | timeout() | Ming.routing_key()) :: Ming.resp()
      def send(command, opts \\ [])

      def send(command, :infinity) when is_struct(command),
        do: do_send(command.__struct__, command, timeout: :infinity)

      def send(command, timeout) when is_struct(command) and is_integer(timeout),
        do: do_send(command.__struct__, command, timeout: timeout)

      def send(command, routing_key) when is_atom(routing_key),
        do: do_send(routing_key, command, [])

      def send(command, opts),
        do: do_send(resolve_routing_key(opts, command), command, opts)

      unquote(send_clauses)
      defp do_send(_routing_key, _request, _opts), do: {:error, :unregistered_command}

      @doc """
      Routes an event to all corresponding routers for execution.
      """
      @spec publish(any(), keyword(Ming.publish_opts()) | timeout() | Ming.routing_key()) ::
              Ming.resp() | [Ming.resp()]
      def publish(event, opts \\ [])

      def publish(event, :infinity) when is_struct(event),
        do: do_publish(event.__struct__, event, timeout: :infinity)

      def publish(event, timeout) when is_struct(event) and is_integer(timeout),
        do: do_publish(event.__struct__, event, timeout: timeout)

      def publish(event, routing_key) when is_atom(routing_key),
        do: do_publish(routing_key, event, [])

      def publish(event, opts),
        do: do_publish(resolve_routing_key(opts, event), event, opts)

      unquote(publish_clauses)
      defp do_publish(_routing_key, _request, _opts), do: {:error, :unregistered_command}

      defp resolve_routing_key(opts, request) when is_struct(request),
        do: Keyword.get(opts, :routing_key, request.__struct__)

      defp resolve_routing_key(opts, request), do: Keyword.fetch!(opts, :routing_key)

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
