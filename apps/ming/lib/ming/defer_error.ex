defmodule Ming.DeferError do
  @moduledoc """
  Raised by a handler to settle the consumed message with a defer instead of
  returning a consumer action.

  The batch processing strategy rescues this exception and defers the message
  for `:delay` milliseconds (see `Ming.Messaging.BatchProcessing`).
  """
  defexception message: "message processing deferred", delay: 5_000
end
