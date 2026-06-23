defmodule Ming.CommandProcessor do
  defmacro __using__(opts) do
    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :routers, accumulate: true)
    end
  end

  defmacro router(router) do
    for routing_key <- router.__register_routing_keys__() do
      quote generated: true do
        @routers {unquote(routing_key), unquote(router)}
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote generated: true do
      @routing_key_by_module Enum.group_by(@routers, &elem(&1, 0), &elem(&1, 1))

      @doc false
      def send(command, opts \\ [])

      def send(command, :infinity) when is_struct(command),
        do: do_send(command.__struct__, command, timeout: :infinity)

      def send(command, timeout) when is_struct(command) and is_integer(timeout),
        do: do_send(command.__struct__, command, timeout: timeout)

      def send(command, routing_key) when is_atom(routing_key),
        do: do_send(router_key, command, [])

      def send(command, opts),
        do: do_send(resolve_routing_key(opts, command), command, opts)

      for {routing_key, routers} <- @routing_key_by_module do
        @routing_key routing_key
        if Enum.count(routers) == 1 do
          @router Enum.at(routers, 0)

          defp do_send(@routing_key, command, opts), do: @router.send(command, opts)
        else
          defp do_send(@routing_key, _command, _opts), do: {:error, :more_than_one_handler_found}
        end
      end

      defp do_send(_routing_key, _command, _opts), do: {:error, :unregistered_command}

      @doc false
      def publish(event, opts \\ [])

      def publish(event, :infinity) when is_struct(event),
        do: do_publish(event.__struct__, event, timeout: :infinity)

      def publish(event, timeout) when is_struct(command) and is_integer(timeout),
        do: do_publish(event.__struct__, event, timeout: timeout)

      def publish(event, routing_key) when is_atom(routing_key),
        do: do_publish(router_key, event, [])

      def publish(event, opts),
        do: do_publish(resolve_routing_key(opts, event), event, opts)

      for {routing_key, routers} <- @routing_key_by_module do
        @routing_key routing_key
        if Enum.count(routers) == 1 do
          @router Enum.at(routers, 0)

          defp do_publish(@routing_key, event, opts), do: @router.publish(command, opts)
        else
          @routers routers

          defp do_publish(@routing_key, event, opts) do
            case Keyword.get(opts, :execute_mode, :sequencial) do
              :sequencial ->
                Enum.map(
                  @routers,
                  & &1.publish(@routing_key, event, opts)
                )

              :parallel ->
                Task.async_stream(
                  @routers,
                  & &1.publish(@routing_key, event, opts)
                )

              {:parallel, async_opts} ->
                Task.async_stream(
                  @routers,
                  & &1.publish(@routing_key, event, opts),
                  async_opts
                )
            end
          end
        end
      end

      defp do_publish(_routing_key, _command, _opts), do: {:error, :unregistered_command}

      defp resolve_routing_key(opts, request) when is_struct(request),
        do: Keyword.get(opts, :routing_key, request.__struct__)

      defp resolve_routing_key(opts, request), do: Keyword.fetch(opts, :routing_key)
    end
  end
end
