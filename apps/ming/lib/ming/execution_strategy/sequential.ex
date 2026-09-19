defmodule Ming.ExecutionStrategy.Sequential do
  @moduledoc """
  Runs each pipeline one after another, in declaration order.

  Every pipeline receives a fresh copy of the dispatch context, so handlers
  in a publish fan-out stay independent of each other.
  """

  alias Ming.Pipeline

  @behaviour Ming.ExecutionStrategy

  @impl Ming.ExecutionStrategy
  def execute(pipelines, context, _args) do
    Enum.map(pipelines, &Pipeline.run(&1, context))
  end
end
