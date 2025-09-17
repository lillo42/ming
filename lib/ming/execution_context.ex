defmodule Ming.ExecutionContext do
  @moduledoc """
  Defines the execution context structure and operations for command processing in the Ming framework.

  The `ExecutionContext` encapsulates all the necessary information for executing a command,
  including the command itself, correlation data, retry configuration, and metadata. This structure
  is passed through the command handling pipeline and can be modified by middleware components.

  ## Context Fields

  - `:request` - The command to be executed (typically a struct)
  - `:causation_id` - A UUID identifying the command that caused this execution :cite[1]
  - `:correlation_id` - A UUID used to correlate related commands and events :cite[1]
  - `:handler` - The module responsible for handling the command
  - `:function` - The function name (as atom) that handles the command (defaults to `:execute`)
  - `:before_execute` - Optional function to prepare the command before execution :cite[1]
  - `:retry_attempts` - Number of retry attempts remaining for handling failures
  - `:returning` - Specifies what should be returned from successful execution
  - `:metadata` - Key/value pairs of metadata associated with the execution

  ## Usage


  The execution context flows through the command processing pipeline, allowing middleware
  to intercept and transform the context at various stages. It supports retry mechanisms
  and flexible response formatting based on the configured return options.
  """

  defstruct [
    :request,
    :causation_id,
    :correlation_id,
    :handler,
    :function,
    before_execute: nil,
    retry_attempts: 0,
    returning: false,
    metadata: %{}
  ]

  @doc """
  Attempts to retry the execution by decrementing the retry attempts counter.

  This function is used when command execution fails and retry logic should be applied.
  It returns an updated context with decremented retry attempts or an error if no
  retries remain.

  ## Parameters
  - `context`: The current `Ming.ExecutionContext.t()`

  ## Returns
  - `{:ok, updated_context}` if retries are available
  - `{:error, :too_many_attempts}` if no retries remain


  ## Examples
      case Ming.ExecutionContext.retry(context) do
        {:ok, updated_context} -> 
          # Retry with updated context
        {:error, :too_many_attempts} -> 
          # Handle retry exhaustion

      end
  """
  def retry(%__MODULE__{retry_attempts: nil}),
    do: {:error, :too_many_attempts}

  def retry(%__MODULE__{retry_attempts: retry_attempts}) when retry_attempts <= 0,
    do: {:error, :too_many_attempts}

  def retry(%__MODULE__{} = context) do
    %__MODULE__{retry_attempts: retry_attempts} = context

    context = %__MODULE__{context | retry_attempts: retry_attempts - 1}

    {:ok, context}
  end

  @doc """
  Formats the reply from command execution based on the context's return configuration.

  This function transforms the raw execution result into the appropriate response format
  based on the `:returning` option configured in the execution context.

  ## Parameters
  - `reply`: The raw execution result tuple (`{:ok, events}` or `{:error, error}`)
  - `context`: The current `Ming.ExecutionContext.t()` with return configuration

  ## Returns
  - Formatted response based on the context's `:returning` setting:

    - `:events` -> `{:ok, list_of_events}`
    - `:execution_result` -> `{:ok, %Ming.ExecutionResult{}}`

    - `false` or `nil` -> `:ok`

  ## Examples
      # With returning: :events
      format_reply({:ok, [event1, event2]}, context) 
      # => {:ok, [event1, event2]}

      # With returning: :execution_result  
      format_reply({:ok, [event1, event2]}, context)
      # => {:ok, %Ming.ExecutionResult{events: [event1, event2], metadata: %{}}}


      # With returning: false
      format_reply({:ok, [event1, event2]}, context)
      # => :ok
  """
  def format_reply({:ok, events}, %__MODULE__{} = context) do
    %__MODULE__{metadata: metadata, returning: returning} = context

    case returning do
      :events ->
        {:ok, events}

      :execution_result ->
        result = %Ming.ExecutionResult{
          events: events,
          metadata: metadata
        }

        {:ok, result}

      false ->
        :ok

      nil ->
        :ok
    end
  end

  def format_reply({:error, _error} = reply, _context) do
    reply
  end

  def format_reply({:error, error, _stacktrace}, _context) do
    {:error, error}
  end
end
