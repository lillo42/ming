defmodule Ming.Dispatcher do
  require Logger

  alias Ming.Context

  def dispatch(%Context{timeout: timeout} = context) when is_number(timeout) and timeout > 0 do
    task = Task.async(fn -> do_dispatcher(context) end)

    case Task.yield(task, timeout) do
      {:ok, context} ->
        Logger.debug("executed with success")
        context

      {:exit, reason} ->
        Logger.error("error during executing pipeline")

        context
        |> Context.halt()
        |> Context.respond({:error, reason})

      nil ->
        Logger.warning("timeout during executing, going to shutdown")

        Task.shutdown(task)

        context
        |> Context.halt()
        |> Context.respond({:error, :timeout})
    end
  end

  def dispatch(%Context{} = context) do
    try do
      do_dispatcher(context)
    rescue
      error ->
        Logger.error("error during executing pipeline")

        context
        |> Context.halt()
        |> Context.respond({:error, error})
    end
  end

  defp do_dispatcher(%Context{} = context) do
    context
    |> do_before()
    |> do_after()
  end

  defp do_before(%Context{} = context) do
    Enum.reduce_while(context.middlewares, {context, []}, fn middleware, acc ->
      {context, middlewares} = acc

      context = middleware.before_handle(context)

      if Context.halted?(context) do
        {:halt, {context, middlewares}}
      else
        {:cont, {context, [middleware | middlewares]}}
      end
    end)
  end

  defp do_after({%Context{} = context, middlewares}) when is_list(middlewares) do
    Enum.reduce(middlewares, context, fn middleware, acc ->
      context = acc
      middleware.after_handle(context)
    end)
  end
end
