defmodule Ming.Messaging.InMemory.Queue do
  @moduledoc """
  A named FIFO queue process backing the in-memory gateway.

  Queues are registered locally under the resolved name (see
  `resolve_name/1`) so producers and consumers can reach them by the queue
  name declared in the gateway configuration.
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, :queue.new(), opts)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_info({:push, item}, queue), do: {:noreply, :queue.in(item, queue)}

  @impl true
  def handle_cast({:push, item}, queue), do: {:noreply, :queue.in(item, queue)}

  def handle_cast({:push, item, delay}, queue) do
    Process.send_after(self(), {:push, item}, delay)
    {:noreply, queue}
  end

  @impl true
  def handle_call({:pop, buffer_size}, _from, queue) do
    {messages, queue} = pop(buffer_size, queue, [])
    {:reply, Enum.reverse(messages), queue}
  end

  defp pop(0, queue, acc), do: {acc, queue}

  defp pop(buffer_size, queue, acc) do
    case :queue.out(queue) do
      {{:value, item}, new_queue} ->
        pop(buffer_size - 1, new_queue, [item | acc])

      {:empty, new_queue} ->
        pop(0, new_queue, acc)
    end
  end

  @doc """
  Resolves a configured queue name into a locally registered process name.

  Atom names are used as-is; string names are converted to atoms, so they
  should come from static configuration rather than user input.
  """
  def resolve_name(name) when is_atom(name), do: name
  def resolve_name(name) when is_binary(name), do: String.to_atom(name)

  def push(queue, item), do: GenServer.cast(resolve_name(queue), {:push, item})

  def push(queue, item, delay), do: GenServer.cast(resolve_name(queue), {:push, item, delay})

  def poll(queue, buffer_size), do: GenServer.call(resolve_name(queue), {:pop, buffer_size})
end
