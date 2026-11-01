defmodule Ming.Messaging.Brod.Buffer do
  @moduledoc """
  Per-subscription buffer between the `:brod` group subscriber (push)
  and the `Ming.Messaging.Brod.Consumer`, which drains it into the
  subscription's `Ming.Messaging.Processor`.

  Messages pushed by subscriber workers are held in a FIFO queue until a
  consumer takes them. `take/3` blocks — the caller is held by the
  GenServer and replied to as soon as a message is pushed — so an idle
  subscription costs no polling wakeups. Callers that waited `wait`
  milliseconds without the queue filling are replied with the messages
  available so far (or `[]`).

  The queue is unbounded; the number of unprocessed messages in flight is
  bounded upstream by the subscription's `:consumer_config` prefetch
  window (`prefetch_count`/`prefetch_bytes`), because subscriber workers
  only release the window when Ming acks the message.

  Messages are lost if the buffer process crashes before they are
  settled; since their offsets were never committed, Kafka redelivers
  them.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  Appends the message to the back of the queue, waking a waiting taker.
  """
  def push(name, message), do: GenServer.cast(name, {:push, message})

  @doc """
  Takes up to `count` messages, waiting up to `wait` milliseconds for at
  least one when the queue is empty.
  """
  def take(name, count, wait \\ 5_000) do
    GenServer.call(name, {:take, count, wait}, wait + 5_000)
  end

  @impl true
  def init(_opts) do
    {:ok, %{queue: :queue.new(), waiters: :queue.new()}}
  end

  @impl true
  def handle_cast({:push, message}, state) do
    {:noreply, state |> enqueue(message) |> serve_waiters()}
  end

  @impl true
  def handle_info({:waiter_timeout, ref}, state) do
    case pop_waiter(state.waiters, ref) do
      nil ->
        {:noreply, state}

      {waiter, waiters} ->
        GenServer.reply(waiter.from, [])
        {:noreply, %{state | waiters: waiters}}
    end
  end

  @impl true
  def handle_call({:take, count, wait}, from, state) do
    if :queue.is_empty(state.queue) and wait > 0 do
      ref = make_ref()
      timer = Process.send_after(self(), {:waiter_timeout, ref}, wait)
      waiter = %{from: from, count: count, ref: ref, timer: timer}

      {:noreply, %{state | waiters: :queue.in(waiter, state.waiters)}}
    else
      {messages, queue} = take_all(state.queue, count, [])
      {:reply, messages, %{state | queue: queue}}
    end
  end

  defp enqueue(state, message), do: %{state | queue: :queue.in(message, state.queue)}

  defp serve_waiters(state) do
    case :queue.out(state.waiters) do
      {:empty, _waiters} ->
        state

      {{:value, waiter}, waiters} ->
        if :queue.is_empty(state.queue) do
          state
        else
          {messages, queue} = take_all(state.queue, waiter.count, [])
          Process.cancel_timer(waiter.timer)
          GenServer.reply(waiter.from, messages)

          serve_waiters(%{state | queue: queue, waiters: waiters})
        end
    end
  end

  defp take_all(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp take_all(queue, count, acc) do
    case :queue.out(queue) do
      {:empty, queue} -> {Enum.reverse(acc), queue}
      {{:value, message}, queue} -> take_all(queue, count - 1, [message | acc])
    end
  end

  defp pop_waiter(waiters, ref) do
    waiters
    |> :queue.to_list()
    |> Enum.split_with(&(&1.ref == ref))
    |> case do
      {[], _waiters} -> nil
      {[waiter], rest} -> {waiter, :queue.from_list(rest)}
    end
  end
end
