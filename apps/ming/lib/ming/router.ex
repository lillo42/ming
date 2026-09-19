defmodule Ming.Router do
  @moduledoc """
  Declarative router that maps routing keys to pipelines.

  A router only collects declarations — routing keys, handlers and
  middleware — which a `Ming.Dispatcher` then imports with `router/1`:

      defmodule MyApp.Router do
        use Ming.Router

        middleware MyApp.AuthMiddleware

        routing_key "orders.created", handler: MyApp.CreateOrderHandler
        routing_key ["orders.paid", "orders.refunded"], handler: MyApp.BillingHandler
      end

  Each `routing_key` declaration builds one pipeline per handler: the given
  middlewares followed by a terminal `Ming.Middleware.HandlerRunner` that
  invokes the handler. Middleware declared at router level wraps every
  pipeline in the router.
  """

  @doc false
  defmacro __using__(opts) do
    metadata = Keyword.get(opts, :metadata, Macro.escape(%{}))
    timeout = Keyword.get(opts, :timeout, :infinity)

    quote do
      import Ming.Registration

      @before_compile unquote(__MODULE__)

      Module.register_attribute(__MODULE__, :routing_keys, accumulate: true)
      Module.register_attribute(__MODULE__, :middlewares, accumulate: true)

      @default_opts [
        metadata: unquote(metadata),
        timeout: unquote(timeout)
      ]
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    routing_keys = env.module |> Module.get_attribute(:routing_keys) |> Enum.reverse()
    middlewares = env.module |> Module.get_attribute(:middlewares) |> Enum.reverse()

    final =
      Enum.map(routing_keys, fn {key, opts} ->
        Keyword.update(opts, :middlewares, middlewares, &(middlewares ++ &1))
        |> then(&{key, &1})
      end)

    quote generated: true do
      @doc """
      Returns the declared routing keys as `{key, opts}` tuples.
      """
      @spec __routing_keys__() :: [{Ming.routing_key(), keyword()}]
      def __routing_keys__, do: unquote(Macro.escape(final))
    end
  end
end
