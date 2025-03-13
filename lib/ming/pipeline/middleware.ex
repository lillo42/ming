defmodule Ming.Pipeline.Middleware do
  @moduledoc """
  Middleware provides an extension point to add functions that you want to be
  called for every command the router dispatches.

  Examples include message mapper, inbox pattern, outbox pattern, and logging.

  Implement the `Ming.Pipeline.Middleware` behaviour in your module and define the
  `c:before_dispatch/1`, `c:after_dispatch/1`, and `c:after_failure/1` callback
  functions.

  ## Example middleware

      defmodule NoOpMiddleware do
        @behaviour Ming.Pipeline.Middleware

        alias Commanded.Middleware.Pipeline
        import Pipeline

        def before_dispatch(%Pipeline{command: command} = pipeline) do
          pipeline
        end

        def after_dispatch(%Pipeline{command: command} = pipeline) do
          pipeline
        end

        def after_failure(%Pipeline{command: command} = pipeline) do
          pipeline
        end
      end
  """

  @type pipeline :: %Ming.Pipeline{}

  @callback before_dispatch(pipeline()) :: pipeline()
  @callback after_dispatch(pipeline()) :: pipeline()
  @callback after_failure(pipeline()) :: pipeline()
end
