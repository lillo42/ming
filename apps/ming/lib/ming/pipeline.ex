defmodule Ming.Pipeline do
  @moduledoc """
  An ordered chain of middleware executed around a handler.

  Middleware is stored as `{module, opts}` tuples and sorted by the `:order`
  option (default `0`). Running a pipeline folds the middleware list into
  nested `execute/3` calls, so each middleware wraps the rest of the chain
  and can run logic before and after calling `next`.
  """

  alias Ming.Context

  @enforce_keys [:middlewares]
  defstruct [:middlewares]

  @type middleware :: {module(), keyword()}
  @type t :: %__MODULE__{middlewares: [middleware()]}

  @doc """
  Appends middleware to the pipeline and re-sorts by `:order`.
  """
  @spec concat(t(), middleware() | [middleware()]) :: t()
  def concat(%__MODULE__{} = pipeline, []), do: pipeline

  def concat(%__MODULE__{} = pipeline, middlewares) do
    middlewares =
      (pipeline.middlewares ++ List.wrap(middlewares))
      |> Enum.sort_by(fn {_module, opts} -> Keyword.get(opts, :order, 0) end)

    %__MODULE__{middlewares: middlewares}
  end

  @doc """
  Runs the pipeline for the given context.

  When `context.timeout` is an integer, the pipeline runs in a task and the
  context is answered with `{:error, :timeout}` if it does not finish in
  time.
  """
  @spec run(t(), Context.t()) :: Context.t()
  def run(%__MODULE__{middlewares: middlewares}, %Context{timeout: :infinity} = context) do
    do_run(middlewares, context)
  end

  def run(%__MODULE__{middlewares: middlewares}, %Context{timeout: timeout} = context) do
    caller = self()

    {pid, ref} =
      spawn_monitor(fn -> send(caller, {self(), do_run(middlewares, context)}) end)

    receive do
      {^pid, result} ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ^ref, :process, ^pid, reason} ->
        exit(reason)
    after
      timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(ref, [:flush])
        Context.respond(context, {:error, :timeout})
    end
  end

  defp do_run([], context), do: context

  defp do_run([{middleware, opts} | rest], context) do
    middleware.execute(context, Keyword.get(opts, :args), &do_run(rest, &1))
  end
end
