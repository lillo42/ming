defmodule Ming.Dispatcher do
  @moduledoc false

  alias Ming.Dispatcher.Payload
  alias Ming.ExecutionContext
  alias Ming.Handler
  alias Ming.Pipeline
  alias Ming.Telemetry

  require Logger

  defmodule Payload do
    @moduledoc false

    @type t :: %__MODULE__{}

    defstruct [
      :application,
      :request,
      :request_uuid,
      :correlation_id,
      :handler_module,
      :handler_function,
      :handler_before_execute,
      :timeout,
      :metadata,
      :retry_attempts,
      :returning,
      middleware: []
    ]
  end

  # Dispatch the given command to the handler module for the aggregate as
  # identified.
  # @spec dispatch(payload :: Payload.t()) :: Router.dispatch_resp() | {:ok, events :: list(struct())}
  def dispatch(%Payload{} = payload) do
    pipeline = to_pipeline(payload)
    telemetry_metadata = telemetry_metadata(pipeline, payload)

    start_time = telemetry_start(telemetry_metadata)

    pipeline = before_dispatch(pipeline, payload)

    # Stop command execution if pipeline has been halted
    unless Pipeline.halted?(pipeline) do
      context = to_execution_context(pipeline, payload)

      pipeline
      |> execute(payload, context)
      |> telemetry_stop(start_time, telemetry_metadata)
      |> Pipeline.response()
    else
      pipeline
      |> after_failure(payload)
      |> telemetry_stop(start_time, telemetry_metadata)
      |> Pipeline.response()
    end
  end

  defp to_pipeline(%Payload{} = payload) do
    struct(Pipeline, Map.from_struct(payload))
  end

  defp execute(%Pipeline{} = pipeline, %Payload{} = payload, %ExecutionContext{} = context) do
    %Pipeline{application: application} = pipeline
    %Payload{timeout: timeout} = payload

    result = Handler.execute(application, context, timeout)

    case result do
      {:ok, response} ->
        pipeline
        |> Pipeline.assign(:response, response)
        |> after_dispatch(payload)
        |> Pipeline.respond(:ok)

      {:error, :handler_execution_timeout} ->
        # Maybe retry command when aggregate process not found on a remote node
        maybe_retry(pipeline, payload, context)

      {:error, error} ->
        pipeline
        |> Pipeline.respond({:error, error})
        |> after_failure(payload)

      {:error, error, reason} ->
        pipeline
        |> Pipeline.assign(:error_reason, reason)
        |> Pipeline.respond({:error, error})
        |> after_failure(payload)
    end
  end

  defp to_execution_context(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Pipeline{request: request, request_uuid: resquest_uuid, metadata: metadata} = pipeline

    %Payload{
      correlation_id: correlation_id,
      handler_module: handler_module,
      handler_function: handler_function,
      handler_before_execute: handler_before_execute,
      retry_attempts: retry_attempts,
      returning: returning
    } = payload

    %ExecutionContext{
      request: request,
      causation_id: resquest_uuid,
      correlation_id: correlation_id,
      metadata: metadata,
      handler: handler_module,
      function: handler_function,
      before_execute: handler_before_execute,
      retry_attempts: retry_attempts,
      returning: returning
    }
  end

  defp before_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :before_dispatch, middleware)
  end

  defp after_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :after_dispatch, middleware)
  end

  defp after_failure(%Pipeline{response: {:error, error}} = pipeline, %Payload{} = payload) do
    %Payload{middleware: middleware} = payload

    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(
         %Pipeline{response: {:error, error, reason}} = pipeline,
         %Payload{} = payload
       ) do
    %Payload{middleware: middleware} = payload

    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.assign(:error_reason, reason)
    |> Pipeline.chain(:after_failure, middleware)
  end

  defp after_failure(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Payload{middleware: middleware} = payload

    Pipeline.chain(pipeline, :after_failure, middleware)
  end

  defp telemetry_start(telemetry_metadata) do
    Telemetry.start([:commanded, :application, :dispatch], telemetry_metadata)
  end

  defp telemetry_stop(%Pipeline{assigns: assigns} = pipeline, start_time, telemetry_metadata) do
    event_prefix = [:commanded, :application, :dispatch]

    case assigns do
      %{error: error} ->
        Telemetry.stop(event_prefix, start_time, Map.put(telemetry_metadata, :error, error))

      _ ->
        Telemetry.stop(event_prefix, start_time, telemetry_metadata)
    end

    pipeline
  end

  defp telemetry_metadata(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Payload{application: application} = payload

    context = to_execution_context(pipeline, payload)

    %{
      application: application,
      error: nil,
      execution_context: context
    }
  end

  defp maybe_retry(pipeline, payload, context) do
    case ExecutionContext.retry(context) do
      {:ok, context} ->
        execute(pipeline, payload, context)

      reply ->
        reply
    end
  end
end
