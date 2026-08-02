defmodule Ming.Dispatcher do
  @moduledoc """
  Executes the middleware pipeline for a given `Ming.Context`.

  When a numeric timeout is configured, dispatch runs in a task and is bounded
  by that timeout. Otherwise it runs in-process.

  ## Retries

  When the context carries a `:retry` option — a keyword list of
  `Ming.retry_opts()` or a plain max-retries integer — any `{:error, _}`
  response (including handler exceptions and timeouts) re-runs the whole
  pipeline with a backoff delay computed by `Ming.Gateway.RetryConfig`,
  until it succeeds or the retries are exhausted. Each attempt runs the
  full middleware chain, emits its own telemetry span, and a numeric
  timeout applies per attempt.

  ## Telemetry

  The dispatcher emits the following telemetry events using `:telemetry.span/3`:

  * `[:ming, :dispatch, :start]` - Executed before the dispatch pipeline starts.
  * `[:ming, :dispatch, :stop]` - Executed after the pipeline completes successfully.
  * `[:ming, :dispatch, :exception]` - Executed when the pipeline raises an exception.

  All events receive the following metadata:
  * `:handler` - The module handling the request
  * `:pid` - The PID of the process executing the pipeline
  * `:request_id` - The unique ID of the request
  * `:correlation_id` - The correlation ID of the request
  * `:routing_key` - The routing key used
  * `:timeout` - The configured timeout
  """

  require Logger

  alias Ming.Context
  alias Ming.Gateway.RetryConfig

  @doc """
  Dispatches a context through the middleware pipeline.
  """
  def dispatch(%Context{} = context) do
    do_dispatch(context, retry_config(context.retry), 0)
  end

  defp do_dispatch(%Context{} = context, nil, _attempt), do: run(context)

  defp do_dispatch(%Context{} = context, %RetryConfig{} = config, attempt) do
    result = run(context)

    case {Context.response(result), attempt < config.max_retries} do
      {{:error, _reason}, true} ->
        delay = RetryConfig.calculate_delay(config, attempt)

        Logger.warning(
          "retrying request (attempt #{attempt + 1}/#{config.max_retries})",
          Keyword.merge(log_metadata(context), attempt: attempt + 1, retry_delay: delay)
        )

        Process.sleep(delay)

        do_dispatch(context, config, attempt + 1)

      _response ->
        result
    end
  end

  defp retry_config(nil), do: nil
  defp retry_config(false), do: nil

  defp retry_config(max_retries) when is_integer(max_retries) and max_retries >= 0,
    do: RetryConfig.new(max_retries: max_retries)

  defp retry_config(opts) when is_list(opts), do: RetryConfig.new(opts)

  defp run(%Context{timeout: timeout} = context) when is_number(timeout) and timeout > 0 do
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

  defp run(%Context{} = context) do
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

      # Always include the current middleware in the after-chain,
      # even if it halts, so its after_handle is unwound.
      middlewares = [middleware | middlewares]

      if Context.halted?(context) do
        {:halt, {context, middlewares}}
      else
        {:cont, {context, middlewares}}
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
      correlation_id: context.correlation_id,
      routing_key: context.routing_key,
      timeout: context.timeout
    }
  end

  defp log_metadata(%Context{} = context) do
    [
      handler: context.handler,
      pid: self(),
      request_id: context.id,
      correlation_id: context.correlation_id,
      routing_key: context.routing_key,
      timeout: context.timeout
    ]
  end
end
