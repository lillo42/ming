defmodule Ming.Middleware do
  @moduledoc """
  Behaviour for middleware participating in request dispatch.

  Middleware runs in two phases:
  - `before_handle/1` while entering the pipeline
  - `after_handle/1` while unwinding the pipeline

  ## Halting

  A middleware can stop the pipeline by calling `Ming.Context.halt/1`.
  When halted, downstream middlewares are skipped, but the halting
  middleware's `after_handle/1` is still called during unwind.

  ## Example

      defmodule MyApp.LoggingMiddleware do
        @behaviour Ming.Middleware

        def before_handle(context) do
          IO.puts("Starting \#{context.routing_key}")
          context
        end

        def after_handle(context) do
          IO.puts("Finished \#{context.routing_key}")
          context
        end
      end
  """

  alias Ming.Context

  @doc """
  Runs before the handler execution stage.
  """
  @callback before_handle(context :: Context.t()) :: Context.t()

  @doc """
  Runs after the handler execution stage.

  This is called even if the pipeline was halted by this middleware's
  `before_handle/1`, allowing for cleanup or logging.
  """
  @callback after_handle(context :: Context.t()) :: Context.t()
end
