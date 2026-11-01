defmodule Ming.Messaging.Processor do
  @moduledoc """
  Batches pushed messages and dispatches each batch through the
  subscription's batch processing strategy.

  One `Processor` process serves one consumer of one subscription. It is
  started by the dispatcher's supervision tree (see `Ming.Dispatcher`)
  under a deterministic registered name (see `child_name/3`), and fed by
  a consumer process calling `push/2` — for example
  `Ming.Messaging.InMemory.Consumer`.

  ## Batching

  Messages arrive one envelope per message and accumulate in the mailbox.
  Each received message triggers a non-blocking drain that pulls up to
  `:buffer_size` (default `10`) queued messages, preserving their order,
  and hands the batch to the strategy resolved from the subscription's
  `:batch_processing` (see `Ming.Messaging.BatchProcessing`). Because the
  drain uses a selective receive on the raw envelope, other messages
  (monitors, timeouts) interleaved in the mailbox are skipped and handled
  normally afterwards.

  ## Delivery guarantees

  The mailbox is the only buffer: it is destroyed with the process, so
  messages pushed but not yet processed when the processor crashes are
  lost. Durability must come from the transport below — settle (`ack/2`,
  `nack/2`, `defer/3` on the `Ming.Messaging.Consumer` behaviour) only
  after the batch is processed, so the broker can redeliver.
  """
  use GenServer, restart: :transient

  alias Ming.Messaging.BatchProcessing

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  Pushes a batch of messages into the processor's mailbox, one envelope
  per message, returning `:ok`. Returns `:empty` for an empty batch
  without touching the processor.

  Uses a raw `send/2` (not `GenServer.cast/2`) so the envelopes can be
  pulled straight out of the mailbox by the batching drain. Raises
  `ArgumentError` when `name` is not registered — callers that race the
  processor's (re)start are expected to check `Process.whereis/1` first.
  """
  def push(_name, []), do: :empty

  def push(name, messages) when is_list(messages) do
    Enum.each(messages, &send(name, {:ming_message, &1}))
    :ok
  end

  @doc """
  Deterministic registered name of the processor consuming `subscription`
  of `gateway` with consumer index `index`. Used both when starting
  processors (see `Ming.Dispatcher`) and when pushing into them.
  """
  def child_name(gateway, subscription, index) do
    :"#{__MODULE__}.#{gateway}.#{subscription}.#{index}"
  end

  @impl true
  def init(opts) do
    subscription = Keyword.fetch!(opts, :subscription)

    {:ok,
     %{
       consumer: Keyword.fetch!(opts, :consumer),
       subscription: subscription,
       dispatcher: Keyword.fetch!(opts, :dispatcher)
     }}
  end

  @impl true
  def handle_info({:ming_message, message}, state) do
    %{
      consumer: consumer,
      dispatcher: dispatcher,
      subscription: subscription
    } = state

    batch = drain([message], Map.get(subscription, :buffer_size, 10) - 1)

    {strategy, args} = BatchProcessing.resolve(subscription.batch_processing)

    strategy.execute(
      batch,
      Keyword.merge(args,
        consumer: consumer,
        subscription: subscription,
        dispatcher: dispatcher
      )
    )

    {:noreply, state}
  end

  defp drain(acc, 0), do: Enum.reverse(acc)

  defp drain(acc, remaining) do
    receive do
      {:ming_message, message} ->
        drain([message | acc], remaining - 1)
    after
      0 -> drain(acc, 0)
    end
  end
end
