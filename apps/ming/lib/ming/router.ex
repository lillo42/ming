defmodule Ming.Router do
  @doc false
  defmacro __using__(opts) do
    metadata = Keyword.get(opts, :metadata, %{}) |> Macro.escape()
    timeout = Keyword.get(opts, :timeout, :infinity)

    quote do
      import unquote(__MODULE__)

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :routing_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :middlewares, accumulate: true)

      @default_opts [
        metadata: unquote(metadata),
        timeout: unquote(timeout)
      ]
    end
  end

  defmacro middleware(middleware, opts \\ []) do
    quote generated: true do
      @middlewares {unquote(middleware), unquote(opts)}
    end
  end

  defmacro routing_key(routing_key, opts \\ []) do
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

  @doc false
  defmacro __before_compile__(_env) do
    quote generated: true do
      @final_routing_keys Enum.map(
                            @routing_keys,
                            fn {key, opts} ->
                              if Enum.empty?(@middlewares) do
                                {key, opts}
                              else
                                middlewares = Keyword.get(opts, :middlewares, [])

                                opts =
                                  Keyword.put(
                                    items,
                                    :middlewares,
                                    middlewares ++ @middlewares
                                  )

                                {key, opts}
                              end
                            end
                          )

      def __routing_keys__, do: @final_routing_keys
    end
  end
end
