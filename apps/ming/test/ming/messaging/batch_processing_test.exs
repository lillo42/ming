defmodule Ming.Messaging.BatchProcessingTest do
  use ExUnit.Case, async: true

  alias Ming.Messaging.BatchProcessing
  alias Ming.Messaging.BatchProcessing.Parallel
  alias Ming.Messaging.BatchProcessing.Sequential
  alias Ming.Messaging.Message

  defmodule FakeConsumer do
    @behaviour Ming.Messaging.Consumer

    def receive_messages(_subscription), do: []

    def ack(subscription, message), do: notify(subscription, {:ack, message.id})

    def nack(subscription, message), do: notify(subscription, {:nack, message.id})

    def defer(subscription, message, delay),
      do: notify(subscription, {:defer, message.id, delay})

    defp notify(subscription, event) do
      Kernel.send(subscription[:test_pid], event)
      :ok
    end
  end

  defmodule FakeDispatcher do
    import Kernel, except: [send: 2]

    def send(message, opts) do
      subscription = opts[:metadata][:ming_subscription]
      Kernel.send(subscription[:test_pid], {:dispatched, message.id, opts[:routing_key]})

      case subscription[:respond] do
        fun when is_function(fun, 1) -> fun.(message)
        response -> response
      end
    end
  end

  defp subscription(extra \\ []) do
    [name: :test, routing_key: :consume, test_pid: self()]
    |> Keyword.merge(extra)
    |> Map.new()
  end

  defp args(subscription) do
    [consumer: FakeConsumer, subscription: subscription, dispatcher: FakeDispatcher]
  end

  defp message(id, partition_key \\ nil) do
    %Message{
      id: id,
      payload: "payload",
      routing_key: :consume,
      timestamp: DateTime.utc_now(),
      partition_key: partition_key
    }
  end

  describe "Sequential" do
    test "acks a message when the pipeline responds successfully" do
      assert :ok = Sequential.execute([message(1)], args(subscription(respond: :ok)))

      assert_received {:dispatched, 1, :consume}
      assert_received {:ack, 1}
    end

    test "settles with the consumer action returned by the pipeline" do
      assert :ok = Sequential.execute([message(1)], args(subscription(respond: {:defer, 100})))

      assert_received {:defer, 1, 100}
    end

    test "settles with the error policy when the pipeline returns an error" do
      assert :ok =
               Sequential.execute([message(1)], args(subscription(respond: {:error, :boom})))

      assert_received {:defer, 1, 5_000}
    end

    test "honors a custom on_error policy" do
      subscription = subscription(respond: {:error, :boom}, on_error: fn _msg, _err -> :nack end)

      assert :ok = Sequential.execute([message(1)], args(subscription))

      assert_received {:nack, 1}
    end

    test "settles raised Ming.DeferError with a defer" do
      respond = fn _message -> raise Ming.DeferError, delay: 42 end

      assert :ok = Sequential.execute([message(1)], args(subscription(respond: respond)))

      assert_received {:defer, 1, 42}
    end

    test "settles raised Ming.NackError with a nack" do
      respond = fn _message -> raise Ming.NackError end

      assert :ok = Sequential.execute([message(1)], args(subscription(respond: respond)))

      assert_received {:nack, 1}
    end

    test "nacks when the error action itself fails" do
      subscription =
        subscription(
          respond: fn _message -> raise "boom" end,
          on_error: fn _msg, _err -> raise "policy failed" end
        )

      assert :ok = Sequential.execute([message(1)], args(subscription))

      assert_received {:nack, 1}
    end

    test "processes messages in order" do
      assert :ok =
               Sequential.execute([message(1), message(2), message(3)], args(subscription()))

      assert_received {:dispatched, 1, :consume}
      assert_received {:dispatched, 2, :consume}
      assert_received {:dispatched, 3, :consume}
      assert_received {:ack, 1}
      assert_received {:ack, 2}
      assert_received {:ack, 3}
    end
  end

  describe "Parallel" do
    test "processes messages with distinct partitions concurrently" do
      respond = fn message ->
        if message.id == :slow, do: Process.sleep(100)
        :ok
      end

      args = args(subscription(respond: respond))

      task =
        Task.async(fn ->
          Parallel.execute([message(:slow, :p1), message(:fast, :p2)], args)
        end)

      assert_receive {:dispatched, :slow, :consume}, 500
      assert_receive {:dispatched, :fast, :consume}, 500
      assert Task.await(task) == :ok
      assert_received {:ack, :slow}
      assert_received {:ack, :fast}
    end

    test "processes messages of the same partition sequentially" do
      respond = fn message ->
        if message.id == :slow, do: Process.sleep(100)
        :ok
      end

      args = args(subscription(respond: respond))

      task =
        Task.async(fn ->
          Parallel.execute([message(:slow, :p1), message(:fast, :p1)], args)
        end)

      assert_receive {:dispatched, :slow, :consume}, 500
      refute_received {:dispatched, :fast, :consume}
      assert Task.await(task) == :ok
      assert_receive {:dispatched, :fast, :consume}, 500
    end

    test "groups null partition keys together when configured" do
      respond = fn message ->
        if message.id == :slow, do: Process.sleep(100)
        :ok
      end

      args =
        args(subscription(respond: respond)) ++ [group_null_partition_keys_together: true]

      task =
        Task.async(fn ->
          Parallel.execute([message(:slow), message(:fast)], args)
        end)

      assert_receive {:dispatched, :slow, :consume}, 500
      refute_received {:dispatched, :fast, :consume}
      assert Task.await(task) == :ok
      assert_receive {:dispatched, :fast, :consume}, 500
    end

    test "runs fully parallel when process_partitions_sequentially is false" do
      respond = fn message ->
        if message.id == :slow, do: Process.sleep(100)
        :ok
      end

      args =
        args(subscription(respond: respond)) ++ [process_partitions_sequentially: false]

      task =
        Task.async(fn ->
          Parallel.execute([message(:slow, :p1), message(:fast, :p1)], args)
        end)

      assert_receive {:dispatched, :slow, :consume}, 500
      assert_receive {:dispatched, :fast, :consume}, 500
      assert Task.await(task) == :ok
    end
  end

  describe "resolve/1" do
    test "resolves shorthand atoms" do
      assert BatchProcessing.resolve(:sequential) == {Sequential, []}
      assert BatchProcessing.resolve(:parallel) == {Parallel, []}
    end

    test "resolves modules and tuples" do
      assert BatchProcessing.resolve(Sequential) == {Sequential, []}

      assert BatchProcessing.resolve({Parallel, max_concurrency: 2}) ==
               {Parallel, [max_concurrency: 2]}
    end
  end
end
