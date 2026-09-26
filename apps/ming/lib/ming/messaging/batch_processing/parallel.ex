defmodule Ming.Messaging.BatchProcessing.Parallel do
  @moduledoc """
  Processes a batch of messages in parallel, optionally preserving sequential
  processing within each partition.

  ## Options

    * `:max_concurrency` — maximum number of messages (or partitions)
      processed at once, defaults to `System.schedulers_online/0`
    * `:process_partitions_sequentially` — when `true` (the default),
      messages sharing a `:partition_key` are processed one at a time, while
      distinct partitions still run in parallel
    * `:group_null_partition_keys_together` — when `false` (the default),
      each message without a `:partition_key` forms its own group and runs
      in parallel with everything else; when `true`, all of them share one
      group and are processed sequentially

  When the subscription sets `:batch_processing_timeout`, each task gets the
  time remaining before the deadline as its timeout; a task killed on timeout
  leaves its message unsettled.
  """

  @behaviour Ming.Messaging.BatchProcessing

  alias Ming.Messaging.BatchProcessing

  @impl true
  def execute(messages, args) do
    subscription = Keyword.fetch!(args, :subscription)
    deadline = BatchProcessing.deadline(subscription[:batch_processing_timeout])

    if Keyword.get(args, :process_partitions_sequentially, true) do
      case group_by_partition(messages, args) do
        :ungrouped ->
          run_parallel(
            messages,
            args,
            deadline,
            &BatchProcessing.process_message(&1, args, deadline)
          )

        groups ->
          run_parallel(groups, args, deadline, fn group ->
            Enum.each(group, &BatchProcessing.process_message(&1, args, deadline))
          end)
      end
    else
      run_parallel(messages, args, deadline, &BatchProcessing.process_message(&1, args, deadline))
    end

    :ok
  end

  defp group_by_partition(messages, args) do
    group_nulls = Keyword.get(args, :group_null_partition_keys_together, false)

    groups =
      Enum.group_by(messages, fn message ->
        case message.partition_key do
          nil when not group_nulls -> {:unique, UUIDv7.generate()}
          partition_key -> partition_key
        end
      end)

    if map_size(groups) == length(messages) do
      :ungrouped
    else
      Map.values(groups)
    end
  end

  defp run_parallel(items, args, deadline, fun) do
    opts = [
      max_concurrency: Keyword.get(args, :max_concurrency, System.schedulers_online()),
      ordered: false,
      timeout: task_timeout(deadline),
      on_timeout: :kill_task
    ]

    items
    |> Task.async_stream(fun, opts)
    |> Stream.run()
  end

  defp task_timeout(nil), do: :infinity
  defp task_timeout(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)
end
