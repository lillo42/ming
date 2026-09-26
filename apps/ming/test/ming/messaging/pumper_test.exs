defmodule Ming.Messaging.PumperTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Ming.Messaging.Message
  alias Ming.Messaging.Pumper

  defmodule ScriptedConsumer do
    @behaviour Ming.Messaging.Consumer

    def receive_messages(subscription) do
      Agent.get_and_update(subscription[:script], fn
        [head | rest] -> {head, rest}
        [] -> {[], []}
      end)
    end

    def ack(subscription, message), do: notify(subscription, {:ack, message.id})
    def nack(subscription, message), do: notify(subscription, {:nack, message.id})

    def defer(subscription, message, delay),
      do: notify(subscription, {:defer, message.id, delay})

    defp notify(subscription, event) do
      if pid = subscription[:test_pid], do: Kernel.send(pid, event)
      :ok
    end
  end

  defmodule FakeDispatcher do
    import Kernel, except: [send: 2]

    def send(message, opts) do
      subscription = opts[:metadata][:subscription]

      if pid = subscription[:test_pid],
        do: Kernel.send(pid, {:dispatched, message.id, opts[:routing_key]})

      :ok
    end
  end

  defmodule FakeStrategy do
    @behaviour Ming.Messaging.BatchProcessing

    def execute(messages, args) do
      Kernel.send(args[:test_pid], {:batch, messages, args[:consumer], args[:dispatcher]})
      :ok
    end
  end

  defp message(id) do
    %Message{id: id, payload: "payload", routing_key: :consume, timestamp: DateTime.utc_now()}
  end

  defp start_pump(scripted, subscription_extra) do
    {:ok, script} = Agent.start_link(fn -> scripted end)

    subscription =
      [name: :test, routing_key: :consume, no_message_delay: 1, failure_delay: 1, script: script]
      |> Keyword.merge(subscription_extra)
      |> Map.new()

    start_supervised!(
      {Pumper, consumer: ScriptedConsumer, subscription: subscription, dispatcher: FakeDispatcher}
    )

    subscription
  end

  test "passes polled batches to the batch processing strategy" do
    start_pump([[message(1)]], batch_processing: {FakeStrategy, [test_pid: self()]})

    assert_receive {:batch, [%Message{id: 1}], ScriptedConsumer, FakeDispatcher}, 500
  end

  test "resolves shorthand batch processing atoms and settles messages" do
    start_pump([[message(1)]], batch_processing: :sequential, test_pid: self())

    assert_receive {:dispatched, 1, :consume}, 500
    assert_receive {:ack, 1}, 500
  end

  test "keeps polling after empty batches" do
    start_pump([[], [message(2)]], batch_processing: {FakeStrategy, [test_pid: self()]})

    assert_receive {:batch, [%Message{id: 2}], _, _}, 500
  end

  test "logs and keeps polling after a receive failure" do
    log =
      capture_log(fn ->
        start_pump([{:error, :boom}, [message(3)]],
          batch_processing: {FakeStrategy, [test_pid: self()]}
        )

        assert_receive {:batch, [%Message{id: 3}], _, _}, 500
      end)

    assert log =~ "pump failed for subscription test"
  end
end
