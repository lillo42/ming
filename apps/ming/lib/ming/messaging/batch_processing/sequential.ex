defmodule Ming.Messaging.BatchProcessing.Sequential do
  @moduledoc """
  Processes each message in a batch one at a time, in the order received.

  When the subscription sets `:batch_processing_timeout`, the remaining time
  budget is shared across the batch: each message gets whichever is smaller —
  its `:message_processing_timeout` or the time left before the deadline.
  """

  @behaviour Ming.Messaging.BatchProcessing

  alias Ming.Messaging.BatchProcessing

  @impl true
  def execute(messages, args) do
    subscription = Keyword.fetch!(args, :subscription)
    deadline = BatchProcessing.deadline(subscription[:batch_processing_timeout])

    Enum.each(messages, &BatchProcessing.process_message(&1, args, deadline))

    :ok
  end
end
