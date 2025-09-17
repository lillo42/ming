defmodule Ming.Dispatcher do
  @moduledoc """
  The core dispatching module for the Ming CQRS framework.

  This module is responsible for processing command payloads through the Ming pipeline,

  executing handlers, managing middleware, and handling retries and errors. It serves as
  the central coordinator for command execution in the Ming framework.

  The dispatcher follows a structured pipeline pattern:
  1. Convert payload to pipeline
  2. Execute before_dispatch middleware
  3. Execute command handler (with retry logic if needed)
  4. Execute after_dispatch middleware on success
  5. Execute after_failure middleware on errors
  6. Return formatted response


  ## Usage

  The dispatcher is typically called by the command processor to handle command execution.
  It manages the complete lifecycle of command processing including telemetry, error handling,
  and middleware execution.
  """

  alias Ming.Dispatcher.Payload
  alias Ming.ExecutionContext
  alias Ming.Handler
  alias Ming.Pipeline
  alias Ming.Telemetry

  require Logger

  defmodule Payload do
    @moduledoc """
    Defines the payload structure for command dispatching.

    This struct contains all the necessary information to execute a command through
    the Ming framework, including handler configuration, middleware, and execution context.

    ## Fields

    - `:application` - The Ming application module
    - `:request` - The command request to be executed
    - `:request_uuid` - Unique identifier for the request
    - `:correlation_id` - Correlation ID for distributed tracing
    - `:handler_module` - Module that handles the command execution
    - `:handler_function` - Function name to call on the handler module (defaults to `:execute`)
    - `:handler_before_execute` - Optional function to prepare the command before execution
    - `:timeout` - Execution timeout in milliseconds
    - `:metadata` - Additional metadata for the execution context
    - `:retry_attempts` - Number of retry attempts remaining
    - `:returning` - Specifies what should be returned from execution (:events, :execution_result, or false)
    - `:middleware` - List of middleware modules to execute during processing
    """

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

  @doc """
  Dispatches a command payload through the Ming execution pipeline.

  This is the main entry point for command execution. It handles the complete
  processing lifecycle including middleware execution, handler invocation,
  error handling, and telemetry.

  ## Parameters
  - `payload`: A `Ming.Dispatcher.Payload.t()` containing command execution details

  ## Returns
  - `:ok` - Command executed successfully (when returning: false)
  - `{:ok, events}` - Command executed successfully with generated events (when returning: :events)
  - `{:ok, execution_result}` - Command executed successfully with execution result (when returning: :execution_result)
  - `{:error, reason}` - Command execution failed

  ## Examples
      payload = %Ming.Dispatcher.Payload{
        application: MyApp,
        request: %OpenAccount{account_number: "ACC123", initial_balance: 1000},
        handler_module: BankAccountHandler,
        timeout: 5000
      }

      case Ming.Dispatcher.dispatch(payload) do
        {:ok, events} -> 
          # Handle successful execution with events
        {:error, reason} -> 

          # Handle execution failure

      end
  """
  @spec dispatch(payload :: Payload.t()) :: :ok | {:ok, any()} | {:error, any()}
  def dispatch(%Payload{} = payload) do
    pipeline = to_pipeline(payload)
    telemetry_metadata = telemetry_metadata(pipeline, payload)

    start_time = telemetry_start(telemetry_metadata)

    pipeline = before_dispatch(pipeline, payload)

    # Stop command execution if pipeline has been halted
    if Pipeline.halted?(pipeline) do
      pipeline
      |> after_failure(payload)
      |> telemetry_stop(start_time, telemetry_metadata)
      |> Pipeline.response()
    else
      context = to_execution_context(pipeline, payload)

      pipeline
      |> execute(payload, context)
      |> telemetry_stop(start_time, telemetry_metadata)
      |> Pipeline.response()
    end
  end

  @doc false
  defp to_pipeline(%Payload{} = payload) do
    struct(Pipeline, Map.from_struct(payload))
  end

  @doc false
  defp execute(%Pipeline{} = pipeline, %Payload{} = payload, %ExecutionContext{} = context) do
    %Pipeline{application: application} = pipeline
    %Payload{timeout: timeout} = payload

    result = Handler.execute(application, context, timeout)

    case result do
      {:ok, response} ->
        pipeline
        |> Pipeline.assign(:response, response)
        |> after_dispatch(payload)
        |> Pipeline.respond(format_reply(response, context))

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

  @doc false
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

  @doc false
  defp before_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :before_dispatch, middleware)
  end

  @doc false
  defp after_dispatch(%Pipeline{} = pipeline, %Payload{middleware: middleware}) do
    Pipeline.chain(pipeline, :after_dispatch, middleware)
  end

  @doc false
  defp after_failure(%Pipeline{response: {:error, error}} = pipeline, %Payload{} = payload) do
    %Payload{middleware: middleware} = payload

    pipeline
    |> Pipeline.assign(:error, error)
    |> Pipeline.chain(:after_failure, middleware)
  end

  @doc false
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

  @doc false
  defp after_failure(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Payload{middleware: middleware} = payload

    Pipeline.chain(pipeline, :after_failure, middleware)
  end

  @doc false
  defp telemetry_start(telemetry_metadata) do
    Telemetry.start([:commanded, :application, :dispatch], telemetry_metadata)
  end

  @doc false
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

  @doc false
  defp telemetry_metadata(%Pipeline{} = pipeline, %Payload{} = payload) do
    %Payload{application: application} = payload

    context = to_execution_context(pipeline, payload)

    %{
      application: application,
      error: nil,
      execution_context: context
    }
  end

  @doc false
  defp maybe_retry(pipeline, payload, context) do
    case ExecutionContext.retry(context) do
      {:ok, context} ->
        execute(pipeline, payload, context)

      reply ->
        pipeline
        |> Pipeline.respond(reply)
        |> after_failure(payload)
    end
  end

  @doc false
  defp format_reply(events, %Ming.ExecutionContext{} = context) do
    Ming.ExecutionContext.format_reply({:ok, events}, context)
  end
end
