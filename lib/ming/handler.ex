defmodule Ming.Handler do
  use TelemetryRegistry

  telemetry_event(%{
    event: [:ming, :handler, :execute, :start],
    description: "Emitted when an handler starts executing a request(command/event)",
    measurements: "%{system_time: integer()}",
    metadata: """
    %{application: Ming.CommandProcessor.t(),
      caller: pid(),
      execution_context: Ming.ExecutionContext.t()}
    """
  })

  telemetry_event(%{
    event: [:ming, :handler, :execute, :stop],
    description: "Emitted when an handler stops executing a request(command/event)",
    measurements: "%{duration: non_neg_integer()}",
    metadata: """
    %{application: Ming.CommandProcessor.t(),
      caller: pid(),
      execution_context: Ming.ExecutionContext.t(),
      response: [map()],
      error: nil | any()}
    """
  })

  telemetry_event(%{
    event: [:ming, :handler, :execute, :exception],
    description: "Emitted when an handler raises an exception",
    measurements: "%{duration: non_neg_integer()}",
    metadata: """
    %{application: Ming.CommandProcessor.t(),
      caller: pid(),
      execution_context: Ming.ExecutionContext.t(),
      kind: :throw | :error | :exit,
      reason: any(),
      stacktrace: list()}
    """
  })

  @moduledoc """
  Handler is a process, it allows execution of commands/event.

  ## Telemetry

  #{telemetry_docs()}
  """

  require Logger

  alias Ming.ExecutionContext
  alias Ming.Telemetry

  @doc """
  Execute the given command against the aggregate.

    - `context` - includes command execution arguments

      (see `Commanded.Aggregates.ExecutionContext` for details).
    - `timeout` - an non-negative integer which specifies how many milliseconds
      to wait for a reply, or the atom :infinity to wait indefinitely.
      The default value is five seconds (5,000ms).


  ## Return values

  Returns `{:ok, response}` on success, or `{:error, error}`
  on failure.

    - `response` - response produced by the handler, can be an empty list.
  """
  def execute(
        application,
        %ExecutionContext{} = context,
        timeout \\ 5_000
      ) do
    task = Task.async(fn -> execute_command(application, context) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} ->
        result

      {:exit, _reason} ->
        {:error, :handler_execution_failed}

      nil ->
        {:error, :handler_execution_timeout}
    end
  end

  defp execute_command(application, %ExecutionContext{} = context) do
    telemetry_metadata = telemetry_metadata(application, context)
    start_time = telemetry_start(telemetry_metadata)

    result = do_execute(context)

    telemetry_stop(start_time, telemetry_metadata, result)

    result
  end

  defp do_execute(%ExecutionContext{} = context) do
    %ExecutionContext{request: request, handler: handler, function: function} = context

    Logger.debug("executing request: " <> inspect(request))

    with :ok <- before_execute_command(context) do
      case apply(handler, function, [request]) do
        {:error, _error} = reply ->
          reply

        {:ok, _response} = reply ->
          reply

        none when none in [:ok, [], nil] ->
          {:ok, []}

        response ->
          {:ok, response}
      end
    else
      {:error, _error} = reply ->
        reply
    end
  rescue
    error ->
      stacktrace = __STACKTRACE__
      Logger.error(Exception.format(:error, error, stacktrace))

      {:error, error, stacktrace}
  end

  defp before_execute_command(%ExecutionContext{before_execute: nil}), do: :ok

  defp before_execute_command(%ExecutionContext{} = context) do
    %ExecutionContext{handler: handler, before_execute: before_execute} = context

    apply(handler, before_execute, [context])
  end

  defp telemetry_metadata(application, %ExecutionContext{} = context) do
    %{
      application: application,
      pid: self(),
      execution_context: context
    }
  end

  defp telemetry_start(telemetry_metadata) do
    Telemetry.start([:ming, :handler, :execute], telemetry_metadata)
  end

  defp telemetry_stop(start_time, telemetry_metadata, result) do
    event_prefix = [:ming, :handler, :execute]

    case result do
      {:ok, events} ->
        Telemetry.stop(event_prefix, start_time, Map.put(telemetry_metadata, :response, events))

      {:error, error} ->
        Telemetry.stop(event_prefix, start_time, Map.put(telemetry_metadata, :error, error))

      {:error, error, stacktrace} ->
        Telemetry.exception(
          event_prefix,
          start_time,
          :error,
          error,
          stacktrace,
          telemetry_metadata
        )
    end
  end
end
