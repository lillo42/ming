defmodule Ming.Middleware do
  @moduledoc """
  Behaviour for pipeline middleware.

  Middleware wraps the rest of the pipeline: it receives the context, its
  own `args`, and a `next` continuation. It can transform the context
  before delegating, inspect or replace the returned context afterwards, or
  short-circuit the pipeline by not calling `next` at all.

      defmodule MyApp.LoggingMiddleware do
        @behaviour Ming.Middleware

        @impl Ming.Middleware
        def execute(context, _args, next) do
          Logger.info("dispatching \#{inspect(context.routing_key)}")
          next.(context)
        end
      end
  """

  alias Ming.Context

  @doc """
  Executes the middleware around the rest of the pipeline.
  """
  @callback execute(
              context :: Context.t(),
              args :: any(),
              next :: (Context.t() -> Context.t())
            ) :: Context.t()
end
