defmodule Ming.Dispatcher do
  @moduledoc """
  Executes the middleware pipeline for a given `Ming.Context`.

  When a numeric timeout is configured, dispatch runs in a task and is bounded
  by that timeout. Otherwise it runs in-process.
  """

  require Logger

  alias Ming.Context

  @doc """
  Dispatches a context through the middleware pipeline.
  """
  def dispatch(%Context{timeout: timeout} = context) when is_number(timeout) and timeout > 0 do
    log_meta = log_metadata(context)

    task = Task.async(fn -> do_dispatcher(context) end)

    case Task.yield(task, timeout) do
      {:ok, context} ->
        Logger.debug("executed with success", log_meta)
        context

      {:exit, reason} ->
        Logger.error(
          "error during executing pipeline",
          Keyword.put(log_meta, :crash_reason, inspect(reason))
        )

        context
        |> Context.halt()
        |> Context.respond({:error, reason})

      nil ->
        Logger.warning("timeout during executing, going to shutdown", log_meta)

        Task.shutdown(task)

        context
        |> Context.halt()
        |> Context.respond({:error, :timeout})
    end
  end

  def dispatch(%Context{} = context) do
    log_meta = log_metadata(context)

    try do
      context = do_dispatcher(context)

      Logger.debug("executed with success", log_meta)
      context
    rescue
      reason ->
        Logger.error(
          "error during executing pipeline",
          Keyword.put(log_meta, :crash_reason, inspect(reason))
        )

        context
        |> Context.halt()
        |> Context.respond({:error, reason})
    end
  end

  defp do_dispatcher(%Context{} = context) do
    telemetry_metadata = telemetry_metadata(context)

    :telemetry.span(
      [:ming, :dispatch],
      telemetry_metadata,
      fn ->
        context =
          context
          |> do_before()
          |> do_after()

        {context, telemetry_metadata}
      end
    )
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

  defp telemetry_metadata(%Context{} = context) do
    %{
      handler: context.handler,
      pid: self(),
      request_id: context.id,
      request_correlation_id: context.correlation_id,
      routing_key: context.routing_key,
      timeout: context.timeout
    }
  end

  defp log_metadata(%Context{} = context) do
    [
      handler: context.handler,
      pid: self(),
      request_id: context.id,
      request_correlation_id: context.correlation_id,
      routing_key: context.routing_key,
      timeout: context.timeout
    ]
  end
end
