defmodule Ming.ExecutionResult do
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
