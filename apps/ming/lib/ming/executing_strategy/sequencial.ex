defmodule Ming.ExecutingStrategy.Sequencial do
  alias Ming.Context
  alias Ming.Pipeline

  @behaviour Ming.ExecutingStrategy

  def execute(context, [], _args), do: context

  def execute(context, pipelines, _args) do
    do_execute(pipelines, context, [])
    |> Enum.reverse()
  end

  defp do_execute([], _context, acc), do: acc

  defp do_execute(
         [pipeline | pipelines],
         %Context{} = context,
         acc
       ) do
    context = Pipeline.run(context, pipeline)
    do_execute(pipelines, context, [context | acc])
  end
end
