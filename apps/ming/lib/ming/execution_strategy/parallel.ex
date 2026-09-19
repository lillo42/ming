defmodule Ming.ExecutionStrategy.Parallel do
  @moduledoc """
  Runs all pipelines concurrently with `Task.async_stream/3`.

  Extra `args` are forwarded as `Task.async_stream/3` options, so
  concurrency can be tuned with `execution_strategy: {Ming.ExecutionStrategy.Parallel, max_concurrency: 4}`.
  The stream timeout defaults to `:infinity` — per-pipeline timeouts are
  already enforced by `Ming.Pipeline.run/2`.
  """

  alias Ming.Pipeline

  @behaviour Ming.ExecutionStrategy

  @impl Ming.ExecutionStrategy
  def execute(pipelines, context, args) do
    opts = Keyword.put_new(args, :timeout, :infinity)

    pipelines
    |> Task.async_stream(&Pipeline.run(&1, context), opts)
    |> Enum.map(fn
      {:ok, context} -> context
      {:exit, reason} -> exit(reason)
    end)
  end
end
