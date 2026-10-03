defmodule Ming.Messaging.InMemory.QueueTest do
  use ExUnit.Case, async: false

  alias Ming.Messaging.InMemory.Queue

  test "push and poll preserve FIFO order" do
    start_supervised!({Queue, name: :queue_test_fifo})

    for item <- 1..5, do: Queue.push(:queue_test_fifo, item)

    assert Queue.poll(:queue_test_fifo, 10) == [1, 2, 3, 4, 5]
    assert Queue.poll(:queue_test_fifo, 10) == []
  end

  test "poll takes at most buffer_size messages and keeps the rest" do
    start_supervised!({Queue, name: :queue_test_buffer})

    for item <- 1..5, do: Queue.push(:queue_test_buffer, item)

    assert Queue.poll(:queue_test_buffer, 2) == [1, 2]
    assert Queue.poll(:queue_test_buffer, 10) == [3, 4, 5]
  end

  test "poll on an empty queue returns an empty list" do
    start_supervised!({Queue, name: :queue_test_empty})

    assert Queue.poll(:queue_test_empty, 10) == []
  end

  test "delayed push becomes pollable after the delay" do
    start_supervised!({Queue, name: :queue_test_delay})

    assert :ok = Queue.push(:queue_test_delay, :late, 20)
    assert Queue.poll(:queue_test_delay, 10) == []

    Process.sleep(100)
    assert Queue.poll(:queue_test_delay, 10) == [:late]
  end

  test "push to an unknown queue returns an error" do
    assert Queue.push(:queue_test_missing_push, :item) ==
             {:error, {:queue_not_found, :queue_test_missing_push}}
  end

  test "poll on an unknown queue returns an error" do
    assert Queue.poll(:queue_test_missing_poll, 10) ==
             {:error, {:queue_not_found, :queue_test_missing_poll}}
  end

  test "string queue names resolve to the same process" do
    start_supervised!({Queue, name: Queue.resolve_name("queue_test.string")})

    assert :ok = Queue.push("queue_test.string", :item)
    assert Queue.poll("queue_test.string", 10) == [:item]
  end

  test "concurrent producers do not fail or lose messages" do
    start_supervised!({Queue, name: :queue_test_concurrent})

    results =
      1..10
      |> Task.async_stream(
        fn producer ->
          for item <- 1..20, do: Queue.push(:queue_test_concurrent, {producer, item})
        end,
        max_concurrency: 10
      )
      |> Enum.to_list()

    for {:ok, pushes} <- results, do: assert(Enum.all?(pushes, &(&1 == :ok)))

    received = for _ <- 1..4, item <- Queue.poll(:queue_test_concurrent, 50), do: item

    assert length(received) == 200
    assert Queue.poll(:queue_test_concurrent, 50) == []
  end
end
