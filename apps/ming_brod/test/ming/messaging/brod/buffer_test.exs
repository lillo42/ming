defmodule Ming.Messaging.Brod.BufferTest do
  use ExUnit.Case, async: true

  alias Ming.Messaging.Brod.Buffer

  defp start_buffer(_context) do
    name = Module.concat(Buffer, "Test#{System.unique_integer([:positive])}")
    start_supervised!({Buffer, name: name}, id: name)
    name
  end

  test "take returns pushed messages in FIFO order", context do
    buffer = start_buffer(context)

    Buffer.push(buffer, :one)
    Buffer.push(buffer, :two)

    assert Buffer.take(buffer, 10) == [:one, :two]
    assert Buffer.take(buffer, 10, 0) == []
  end

  test "take respects the count", context do
    buffer = start_buffer(context)

    for item <- 1..5, do: Buffer.push(buffer, item)

    assert Buffer.take(buffer, 2) == [1, 2]
    assert Buffer.take(buffer, 10) == [3, 4, 5]
  end

  test "take with wait 0 does not block on an empty queue", context do
    buffer = start_buffer(context)

    assert Buffer.take(buffer, 10, 0) == []
  end

  test "take blocks until a message is pushed", context do
    buffer = start_buffer(context)

    task = Task.async(fn -> Buffer.take(buffer, 10, 5_000) end)

    Process.sleep(50)
    Buffer.push(buffer, :late)

    assert Task.await(task) == [:late]
  end

  test "a waiting taker times out with an empty reply", context do
    buffer = start_buffer(context)

    assert Buffer.take(buffer, 10, 50) == []

    Buffer.push(buffer, :after_timeout)
    assert Buffer.take(buffer, 10, 0) == [:after_timeout]
  end

  test "a waiting taker is replied as soon as a message is pushed", context do
    buffer = start_buffer(context)

    task = Task.async(fn -> Buffer.take(buffer, 10, 5_000) end)

    Process.sleep(50)
    Buffer.push(buffer, :one)

    assert Task.await(task) == [:one]

    Buffer.push(buffer, :two)
    assert Buffer.take(buffer, 10, 0) == [:two]
  end

  test "multiple waiters are served in arrival order", context do
    buffer = start_buffer(context)

    first = Task.async(fn -> Buffer.take(buffer, 1, 5_000) end)
    Process.sleep(50)
    second = Task.async(fn -> Buffer.take(buffer, 1, 5_000) end)

    Process.sleep(50)
    Buffer.push(buffer, :one)
    Buffer.push(buffer, :two)

    assert Task.await(first) == [:one]
    assert Task.await(second) == [:two]
  end
end
