defmodule Ming.Messaging.InMemory.Queue do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, :queue.new(), opts)

  @impl true
  def init(state), do: state

  @impl true
  def handle_cast({:push, item}, queue), do: {:noreply, :queue.in(item, queue)}

  def handle_cast({:push, item, delay}, queue) do
    Process.send_after(self(), {:push, item}, delay)
    {:noreply, queue}
  end

  @impl true
  def handle_call({:pop, buffer_size}, _from, queue) do
    {messages, queue} = pop(buffer_size, queue, [])
    {:reply, messages, queue}
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

  def push(queue, item), do: GenServer.cast(queue, {:push, item})
  def push(queue, item, delay), do: GenServer.cast(queue, {:push, item, delay})

  def poll(queue, buffer_size), do: GenServer.call(queue, {:pop, buffer_size})
end
