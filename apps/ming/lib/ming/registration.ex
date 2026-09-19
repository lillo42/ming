defmodule Ming.Registration do
  @moduledoc false

  # Shared declaration macros used by `Ming.Router` and `Ming.Dispatcher`.
  # Both modules register the `:routing_keys` and `:middlewares` attributes
  # (accumulate: true) and define `@default_opts`; the quotes below resolve
  # those attributes in the caller module.

  # Middleware with this order sorts after any user middleware, so the
  # handler invocation stays the terminal step of every pipeline.
  @handler_runner_order 10_000

  defmacro middleware(middleware, opts \\ []) do
    quote generated: true do
      @middlewares {unquote(middleware), unquote(opts)}
    end
  end

  defmacro routing_key(routing_key, opts \\ []) do
    quote generated: true do
      for entry <-
            Ming.Registration.build(unquote(routing_key), unquote(opts), @default_opts) do
        @routing_keys entry
      end
    end
  end

  @doc false
  def build(routing_keys, opts, default_opts) do
    handlers =
      (Keyword.get(opts, :handler) || Keyword.get(opts, :handlers, []))
      |> List.wrap()

    middlewares = Keyword.get(opts, :middlewares, [])

    base =
      opts
      |> Keyword.drop([:handler, :handlers])
      |> then(&Keyword.merge(default_opts, &1))

    for routing_key <- List.wrap(routing_keys),
        pipeline <- pipelines_for(handlers, middlewares) do
      {routing_key, Keyword.put(base, :middlewares, pipeline)}
    end
  end

  defp pipelines_for([], middlewares), do: [middlewares]

  defp pipelines_for(handlers, middlewares) do
    Enum.map(handlers, fn handler ->
      middlewares ++
        [{Ming.Middleware.HandlerRunner, args: handler, order: @handler_runner_order}]
    end)
  end
end
