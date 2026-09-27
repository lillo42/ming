defmodule Ming.InvalidMessageError do
  @moduledoc """
  Raised when a message payload cannot be decoded into the request the
  pipeline expects.

  Batch processing routes messages that fail with this error to the
  subscription's invalid-message handling instead of retrying them (see
  `Ming.Messaging.BatchProcessing`).
  """
  defexception [:message, :reason]
end
