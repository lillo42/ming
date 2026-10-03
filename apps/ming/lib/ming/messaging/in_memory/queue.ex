defmodule Ming.Messaging.InMemory.Queue do
  @moduledoc """
  A named FIFO queue process backing the in-memory gateway.

  Queues are registered locally under the resolved name (see
  `resolve_name/1`) so producers and consumers can reach them by the queue
  name declared in the gateway configuration.

  The queue is unbounded: a producer that outpaces its consumers grows
  the process memory without backpressure.

  `push/2`, `push/3` and `poll/2` return `{:error, {:queue_not_found, name}}`
  when no queue process is registered under the resolved name.
  """
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, :queue.new(), opts)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_info({:push, item}, queue), do: {:noreply, enqueue(item, queue)}

  @impl true
  def handle_call({:push, item}, _from, queue), do: {:reply, :ok, enqueue(item, queue)}

  def handle_call({:push, item, delay}, _from, queue) do
    Process.send_after(self(), {:push, item}, delay)
    {:reply, :ok, queue}
  end

  @impl true
  def handle_call({:pop, buffer_size}, _from, queue) do
    {messages, queue} = pop(buffer_size, queue, [])
    {:reply, Enum.reverse(messages), queue}
  end

  defp enqueue(item, queue), do: :queue.in(item, queue)

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

  def push(queue, item), do: request(queue, {:push, item})

  def push(queue, item, delay), do: request(queue, {:push, item, delay})

  def poll(queue, buffer_size), do: request(queue, {:pop, buffer_size})

  defp request(queue, message) do
    GenServer.call(resolve_name(queue), message)
  catch
    :exit, {reason, _} when reason in [:noproc, :normal] ->
      {:error, {:queue_not_found, queue}}
  end
end
