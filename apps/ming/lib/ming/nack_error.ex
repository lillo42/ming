defmodule Ming.NackError do
  @moduledoc """
  Raised by a handler to settle the consumed message with a nack instead of
  returning a consumer action.

  The batch processing strategy rescues this exception and nacks the message
  (see `Ming.Messaging.BatchProcessing`).
  """
  defexception message: "message processing nacked"
end
