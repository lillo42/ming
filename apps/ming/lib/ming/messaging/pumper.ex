defmodule Ming.Messaging.Pumper do
  @moduledoc """
  Polls a consumer for messages and dispatches each batch through the
  subscription's batch processing strategy.

  One `Pumper` process drives exactly one consumer. On an empty poll it waits
  the subscription's `:no_message_delay` (default 100ms); on a receive failure
  it logs and waits `:failure_delay` (default 5s); after a successful batch it
  polls again immediately.
  """
  use GenServer, restart: :transient

  require Logger

  alias Ming.Messaging.BatchProcessing

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %{
      # module implementing Ming.Messaging.Consumer
      consumer: Keyword.fetch!(opts, :consumer),
      # map with delays, batch_processing, etc.
      subscription: Keyword.fetch!(opts, :subscription),
      # dispatcher module messages are sent through
      dispatcher: Keyword.fetch!(opts, :dispatcher)
    }

    {:ok, state, {:continue, :poll}}
  end

  @impl true
  def handle_continue(:poll, state), do: poll(state)

  @impl true
  def handle_info(:poll, state), do: poll(state)

  defp poll(state) do
    %{consumer: consumer, subscription: subscription} = state

    case consumer.receive_messages(subscription) do
      [] ->
        schedule_next(Map.get(subscription, :no_message_delay, 100))
        {:noreply, state}

      messages when is_list(messages) ->
        {strategy, args} = BatchProcessing.resolve(subscription[:batch_processing])

        strategy.execute(
          messages,
          Keyword.merge(args,
            consumer: consumer,
            subscription: subscription,
            dispatcher: state.dispatcher
          )
        )

        schedule_next(0)
        {:noreply, state}

      {:error, reason} ->
        Logger.error(
          "pump failed for subscription #{Map.get(subscription, :name)}: #{inspect(reason)}"
        )

        schedule_next(Map.get(subscription, :failure_delay, 5_000))
        {:noreply, state}
    end
  end

  defp schedule_next(delay) do
    Process.send_after(self(), :poll, delay)
  end
end
