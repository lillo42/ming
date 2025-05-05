defmodule Ming.ExecutionContext do
  @moduledoc """
  Defines the arguments used to execute a command for an aggregate.

  The available options are:

    - `request` - the command to execute, typically a struct
      (e.g. `%OpenBankAccount{...}`).

    - `retry_attempts` - the number of retries permitted if an
      `{:error, :wrong_expected_version}` is encountered when appending events.

    - `correlation_id` - a UUID used to correlate related commands/events.

    - `metadata` - a map of key/value pairs containing the metadata to be
      associated with all events created by the command.

    - `handler` - the module that handles the command. It may be either the
      aggregate module itself or a separate command handler module.

    - `function` - the name of the function, as an atom, that handles the command.
      The default value is `:execute`, used to support command dispatch directly
      to the aggregate module. For command handlers the `:handle` function is
      used.

    - `before_execute` - the name of the function, as an atom, that prepares the
      command before execution, called just before `function`. The default value
      is `nil`, disabling it. It should return `:ok` on success or `{:error, any()}`
      to cancel the dispatch.
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

  def retry(%__MODULE__{retry_attempts: nil}),
    do: {:error, :too_many_attempts}

  def retry(%__MODULE__{retry_attempts: retry_attempts}) when retry_attempts <= 0,
    do: {:error, :too_many_attempts}

  def retry(%__MODULE__{} = context) do
    %__MODULE__{retry_attempts: retry_attempts} = context

    context = %__MODULE__{context | retry_attempts: retry_attempts - 1}

    {:ok, context}
  end

  def format_reply({:error, _error} = reply, _context, _aggregate) do
    reply
  end

  def format_reply({:error, error, _stacktrace}, _context, _aggregate) do
    {:error, error}
  end
end
