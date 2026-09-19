defmodule Ming.ExecutionStrategy do
  @moduledoc """
  Behaviour for strategies that run the pipelines of a dispatch.

  A dispatch resolves to one pipeline per handler registered for the routing
  key; the strategy decides how those pipelines are executed. Ming ships
  with `Ming.ExecutionStrategy.Sequential` and `Ming.ExecutionStrategy.Parallel`.
  """

  alias Ming.Context
  alias Ming.Pipeline

  @doc """
  Executes every pipeline for the given dispatch context.

  Receives one pipeline per handler registered for the routing key and must
  return the resulting contexts, one per pipeline, in execution order.
  `args` carries strategy-specific options (e.g. `Task.async_stream/3`
  options for `Ming.ExecutionStrategy.Parallel`).
  """
  @callback execute(
              pipelines :: [Pipeline.t()],
              context :: Context.t(),
              args :: keyword()
            ) :: [Context.t()]
end
