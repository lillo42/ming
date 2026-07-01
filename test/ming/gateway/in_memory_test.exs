defmodule Ming.Gateway.InMemoryTest do
  use ExUnit.Case

  alias Ming.Gateway.InMemory
  alias Ming.Gateway.InMemory.Broker
  alias Ming.Gateway.InMemory.Producer
  alias Ming.Message

  defmodule InMemoryFakeProcessor do
    @moduledoc false
    def send(request, opts) do
      Ming.Gateway.InMemoryTest.InMemoryFakeAgent.behavior().(request, opts)
    end
  end

  defmodule InMemoryFakeAgent do
    @moduledoc false
    use Agent

    def start_link(_),
      do: Agent.start_link(fn -> fn _, _ -> :ok end end, name: __MODULE__)

    def set_behavior(fun),
      do: Agent.update(__MODULE__, fn _ -> fun end)

    def behavior,
      do: Agent.get(__MODULE__, fn state -> state end)
  end

  setup do
    start_supervised!(InMemoryFakeAgent)

    gateway_name = :"test_in_memory_gateway_#{System.unique_integer([:positive])}"

    opts = [
      name: gateway_name,
      command_processor: InMemoryFakeProcessor,
      publications: [
        [routing_key: :order_created]
      ],
      subscriptions: [
        [name: :orders, routing_key: :order_created]
      ]
    ]

    pid = start_supervised!({InMemory, opts})

    %{gateway_name: gateway_name, pid: pid}
  end

  describe "start_link/1" do
    test "starts the supervisor", %{pid: pid} do
      assert Process.alive?(pid)
    end

    test "provision_infrastructure/1 returns :ok" do
      assert :ok == InMemory.provision_infrastructure([])
    end

    test "producer/0 returns the producer module" do
      assert InMemory.producer() == Producer
    end
  end

  describe "publishing" do
    test "stores messages in broker history", %{gateway_name: gateway_name} do
      broker_name = InMemory.broker_name(gateway_name)

      message = %Message{
        id: "msg-1",
        payload: "hello",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      :ok = Broker.publish(broker_name, :order_created, message)

      assert [^message] = Broker.history(broker_name, :order_created)
    end

    test "Producer.publish/2 routes message to broker", %{gateway_name: gateway_name} do
      broker_name = InMemory.broker_name(gateway_name)

      message = %Message{
        id: "msg-2",
        payload: "world",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      gateway_config = [
        adapter: InMemory,
        name: gateway_name,
        publications: [[routing_key: :order_created]]
      ]

      publication = [routing_key: :order_created]

      Producer.publish(message, gateway: gateway_config, publication: publication)

      assert [%Message{payload: "world"}] = Broker.history(broker_name, :order_created)
    end
  end

  describe "subscribing" do
    test "consumer receives published messages", %{gateway_name: gateway_name} do
      broker_name = InMemory.broker_name(gateway_name)

      test_pid = self()

      InMemoryFakeAgent.set_behavior(fn request, _opts ->
        send(test_pid, {:processed, request.payload})
        :ok
      end)

      message = %Message{
        id: "msg-3",
        payload: "buy milk",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      :ok = Broker.publish(broker_name, :order_created, message)

      assert_receive {:processed, "buy milk"}, 1_000
    end

    test "consumer acks are handled silently", %{gateway_name: gateway_name} do
      broker_name = InMemory.broker_name(gateway_name)

      InMemoryFakeAgent.set_behavior(fn _request, _opts ->
        :ack
      end)

      message = %Message{
        id: "msg-4",
        payload: "ignore me",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      assert :ok = Broker.publish(broker_name, :order_created, message)
    end
  end

  describe "broker history" do
    test "history is bounded by limit", %{gateway_name: gateway_name} do
      broker_name = InMemory.broker_name(gateway_name)

      Enum.each(1..5, fn i ->
        message = %Message{
          id: "msg-#{i}",
          payload: "payload-#{i}",
          routing_key: :order_created,
          timestamp: DateTime.utc_now()
        }

        :ok = Broker.publish(broker_name, :order_created, message)
      end)

      assert length(Broker.history(broker_name, :order_created, 3)) == 3
    end
  end
end
