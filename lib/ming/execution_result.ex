defmodule Ming.ExecutionResult do
  @moduledoc """
  Contains the aggregate, events, and metadata created by a successfully
  executed command.

  The available fields are:

    - `events` - a list of the created events, it may be an empty list.

    - `metadata` - an map containing the metadata associated with the command
      dispatch.

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
