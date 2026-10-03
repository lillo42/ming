defmodule Ming.Messaging.TelemetryTest do
  use ExUnit.Case, async: false

  alias Ming.Context
  alias Ming.Messaging.BatchProcessing
  alias Ming.Messaging.InMemory
  alias Ming.Messaging.Message
  alias Ming.Messaging.ProduceHandler
  alias Ming.Messaging.Pumper

  def relay(event, measurements, metadata, pid),
    do: Kernel.send(pid, {:telemetry_event, event, measurements, metadata})

  defmodule TelemetryDispatcher do
    use Ming.Dispatcher

    gateway(:local, InMemory.Gateway,
      publications: [[routing_key: :telemetry_test_produce]],
      subscriptions: [[name: :telemetry_test_sub, routing_key: :telemetry_test_produce]]
    )
  end

  defmodule SettleDispatcher do
    import Kernel, except: [send: 2]

    def send(message, _opts) do
      case message.payload do
        "ack" -> :ok
        "error" -> {:error, :boom}
        "defer" -> raise Ming.DeferError, delay: 10
        "nack" -> raise Ming.NackError
      end
    end
  end

  defmodule RecordingConsumer do
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

  setup do
    handler_id = {__MODULE__, make_ref()}

    events =
      for span <- [:produce, :poll, :process], event <- [:start, :stop, :exception] do
        [:ming, span, event]
      end

    :telemetry.attach_many(handler_id, events, &__MODULE__.relay/4, self())
    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  defp message(payload \\ "payload") do
    %Message{
      id: "msg-1",
      correlation_id: "corr-1",
      payload: payload,
      routing_key: :telemetry_test_produce,
      timestamp: DateTime.utc_now()
    }
  end

  describe "[:ming, :produce]" do
    defp produce_context do
      publication = TelemetryDispatcher.__gateways__()[:local].publications |> hd()

      %Context{
        request: message(),
        routing_key: :telemetry_test_produce,
        timeout: :infinity,
        metadata: %{
          ming_publication: publication,
          ming_dispatcher: TelemetryDispatcher,
          ming_routing_key: :telemetry_test_produce
        }
      }
    end

    test "emits a span with the produce result on success" do
      start_supervised!(
        {InMemory.Gateway,
         %{name: :telemetry_gw_ok, publications: [%{routing_key: :telemetry_test_produce}]}}
      )

      assert :ok = ProduceHandler.handle(message(), produce_context())

      assert_receive {:telemetry_event, [:ming, :produce, :start], _,
                      %{
                        gateway: :local,
                        routing_key: :telemetry_test_produce,
                        queue: :telemetry_test_produce,
                        message_id: "msg-1",
                        correlation_id: "corr-1"
                      }}

      assert_receive {:telemetry_event, [:ming, :produce, :stop], %{duration: duration},
                      %{result: :ok}}

      assert is_integer(duration)
    end

    test "emits the producer error in the stop metadata" do
      assert {:error, {:queue_not_found, _}} =
               ProduceHandler.handle(message(), produce_context())

      assert_receive {:telemetry_event, [:ming, :produce, :stop], _,
                      %{result: {:error, {:queue_not_found, :telemetry_test_produce}}}}
    end
  end

  describe "[:ming, :poll]" do
    defp start_pumper(subscription) do
      start_supervised!(
        {Pumper,
         consumer: InMemory.Consumer, subscription: subscription, dispatcher: SettleDispatcher}
      )
    end

    test "emits a span per poll with the batch size" do
      start_supervised!(
        {InMemory.Gateway,
         %{name: :telemetry_gw_poll, publications: [%{routing_key: :telemetry_test_poll}]}}
      )

      start_pumper(%{
        name: :telemetry_poll_sub,
        routing_key: :telemetry_test_poll,
        no_message_delay: 5,
        failure_delay: 5
      })

      assert_receive {:telemetry_event, [:ming, :poll, :stop], _,
                      %{subscription: :telemetry_poll_sub, batch_size: 0}}

      InMemory.Queue.push(:telemetry_test_poll, message())

      assert_receive {:telemetry_event, [:ming, :poll, :stop], _,
                      %{subscription: :telemetry_poll_sub, batch_size: 1}}
    end

    test "emits the receive error in the stop metadata" do
      start_pumper(%{
        name: :telemetry_poll_missing_sub,
        routing_key: :telemetry_test_missing_queue,
        no_message_delay: 5,
        failure_delay: 5
      })

      assert_receive {:telemetry_event, [:ming, :poll, :stop], _,
                      %{
                        subscription: :telemetry_poll_missing_sub,
                        error: {:queue_not_found, :telemetry_test_missing_queue}
                      }}
    end
  end

  describe "[:ming, :process]" do
    defp process(payload) do
      BatchProcessing.process_message(
        message(payload),
        consumer: RecordingConsumer,
        subscription: %{name: :telemetry_process_sub, routing_key: :consume, test_pid: self()},
        dispatcher: SettleDispatcher
      )
    end

    test "emits outcome :ack for a successful dispatch" do
      assert :ok = process("ack")
      assert_receive {:ack, "msg-1"}

      assert_receive {:telemetry_event, [:ming, :process, :stop], %{duration: _},
                      %{
                        subscription: :telemetry_process_sub,
                        message_id: "msg-1",
                        correlation_id: "corr-1",
                        outcome: :ack
                      }}
    end

    test "emits outcome :error for an error response" do
      assert :ok = process("error")
      assert_receive {:defer, "msg-1", 5_000}

      assert_receive {:telemetry_event, [:ming, :process, :stop], _, %{outcome: :error}}
    end

    test "emits outcome :defer when the handler raises Ming.DeferError" do
      assert :ok = process("defer")
      assert_receive {:defer, "msg-1", 10}

      assert_receive {:telemetry_event, [:ming, :process, :stop], _, %{outcome: :defer}}
    end

    test "emits outcome :nack when the handler raises Ming.NackError" do
      assert :ok = process("nack")
      assert_receive {:nack, "msg-1"}

      assert_receive {:telemetry_event, [:ming, :process, :stop], _, %{outcome: :nack}}
    end
  end
end
