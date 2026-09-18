defmodule Ming.Pipeline do
  alias Ming.Context

  @enforce_keys [:middlewares]
  defstruct [:middlewares]

  def concat(%__MODULE__{} = pipeline, []), do: pipeline

  def concat(%__MODULE__{} = pipeline, middlewares) do
    middlewares =
      (pipeline.middlewares ++ List.wrap(middlewares))
      |> Enum.sort(&(Keyword.get(&2, :order, 1) >= Keyword.get(&1, :order, 1)))

    %__MODULE__{
      middlewares: middlewares
    }
  end

  def run(%__MODULE__{middlewares: middlewares}, %Context{timeout: :infinity} = context) do
    do_run(middlewares, context)
  end

  def run(%__MODULE__{middlewares: middlewares}, %Context{timeout: timeout} = context) do
    task =
      Task.async(fn ->
        do_run(middlewares, context)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        Context.respond(context, {:error, :timeout})
    end
  end

  defp do_run([], context), do: context

  defp do_run([{middleware, opts} | next], context) do
    middleware.execute(
      context,
      Keyword.get(opts, :args),
      &do_run(next, &1)
    )
  end
end
