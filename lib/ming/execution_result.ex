defmodule Ming.ExecutionResult do
  @moduledoc """
  Defines a structure for capturing the result of message execution in the Ming framework.

  The `ExecutionResult` encapsulates the outcome of processing a message through the
  Ming pipeline, including any events generated during processing and metadata about
  the execution context.

  This structure is typically returned after successful message processing and is
  used by downstream components to handle the results of the execution.

  ## Fields

  - `:events` - A list of events that were generated during message processing.
    These can be domain events, integration events, or other structured data that
    should be published or handled after successful execution.

  - `:metadata` - A structure containing metadata about the execution context.
    This may include timing information, correlation data, processing metrics,
    or other contextual information about how the message was processed.

  ## Usage

  ExecutionResult is typically created and populated by the final middleware or
  handler in the processing pipeline, then returned to indicate successful
  completion of message processing.
  """

  @type t :: %__MODULE__{
          events: list(struct()),
          metadata: struct()
        }

  @enforce_keys [:events, :metadata]

  defstruct [
    :events,
    :metadata
  ]
end
