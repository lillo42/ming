defmodule Ming.ExecutingStrategy.Parallel do
  alias Ming.Pipeline

  @behaviour Ming.ExecutingStrategy

  def execute(context, [], _args), do: context

  def execute(context, pipelines, args) do
    Task.async_stream(pipelines, &Pipeline.run(context, &1), args)
    |> Enum.to_list()
  end
end
