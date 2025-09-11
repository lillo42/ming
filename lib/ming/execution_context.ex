defmodule Ming.ExecutionContext do
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

  def retry(%__MODULE__{retry_attempts: nil}),
    do: {:error, :too_many_attempts}

  def retry(%__MODULE__{retry_attempts: retry_attempts}) when retry_attempts <= 0,
    do: {:error, :too_many_attempts}

  def retry(%__MODULE__{} = context) do
    %__MODULE__{retry_attempts: retry_attempts} = context

    context = %__MODULE__{context | retry_attempts: retry_attempts - 1}

    {:ok, context}
  end

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
