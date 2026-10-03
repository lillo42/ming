defmodule Ming.Dispatcher.SupervisionTest do
  use ExUnit.Case, async: false

  alias Ming.Messaging.Message

  defmodule RelayHandler do
    @behaviour Ming.Handler

    @impl true
    def handle(request, _context) do
      Kernel.send(Ming.Dispatcher.SupervisionTest.Relay, {:handled, request})
      :ack
    end
  end

  defmodule SupervisedDispatcher do
    use Ming.Dispatcher

    gateway(:local, Ming.Messaging.InMemory.Gateway,
      publications: [[routing_key: :dispatcher_supervision_test_key]],
      subscriptions: [
        [name: :dispatcher_supervision_test_sub, routing_key: :dispatcher_supervision_test_key]
      ]
    )

    routing_key(:dispatcher_supervision_test_key, handler: RelayHandler)
  end

  defmodule DualGatewayDispatcher do
    use Ming.Dispatcher

    gateway(:first, Ming.Messaging.InMemory.Gateway,
      publications: [[routing_key: :dispatcher_supervision_test_first]],
      subscriptions: [
        [
          name: :dispatcher_supervision_test_first_sub,
          routing_key: :dispatcher_supervision_test_first
        ]
      ]
    )

    gateway(:second, Ming.Messaging.InMemory.Gateway,
      publications: [[routing_key: :dispatcher_supervision_test_second]],
      subscriptions: [
        [
          name: :dispatcher_supervision_test_second_sub,
          routing_key: :dispatcher_supervision_test_second
        ]
      ]
    )

    routing_key(:dispatcher_supervision_test_first, handler: RelayHandler)
    routing_key(:dispatcher_supervision_test_second, handler: RelayHandler)
  end

  defmodule MultiConsumerDispatcher do
    use Ming.Dispatcher

    gateway(:local, Ming.Messaging.InMemory.Gateway,
      publications: [[routing_key: :dispatcher_supervision_test_multi]],
      subscriptions: [
        [
          name: :dispatcher_supervision_test_multi_sub,
          routing_key: :dispatcher_supervision_test_multi,
          number_of_consumers: 3
        ]
      ]
    )

    routing_key(:dispatcher_supervision_test_multi, handler: RelayHandler)
  end

  defmodule DeferHandler do
    @behaviour Ming.Handler

    @impl true
    def handle(request, _context) do
      attempt =
        Agent.get_and_update(Ming.Dispatcher.SupervisionTest.DeferCounter, fn n ->
          {n + 1, n + 1}
        end)

      if attempt == 1 do
        {:defer, 20}
      else
        Kernel.send(Ming.Dispatcher.SupervisionTest.Relay, {:handled, request, attempt})
        :ack
      end
    end
  end

  defmodule DeferDispatcher do
    use Ming.Dispatcher

    gateway(:local, Ming.Messaging.InMemory.Gateway,
      publications: [[routing_key: :dispatcher_supervision_test_defer]],
      subscriptions: [
        [
          name: :dispatcher_supervision_test_defer_sub,
          routing_key: :dispatcher_supervision_test_defer
        ]
      ]
    )

    routing_key(:dispatcher_supervision_test_defer, handler: DeferHandler)
  end

  defmodule BadConsumerCountDispatcher do
    use Ming.Dispatcher

    gateway(:local, Ming.Messaging.InMemory.Gateway,
      publications: [[routing_key: :dispatcher_supervision_test_bad]],
      subscriptions: [
        [
          name: :dispatcher_supervision_test_bad_sub,
          routing_key: :dispatcher_supervision_test_bad,
          number_of_consumers: 0
        ]
      ]
    )

    routing_key(:dispatcher_supervision_test_bad, handler: RelayHandler)
  end

  test "starts the gateway and pumps posted messages to the subscription handler" do
    Process.register(self(), Ming.Dispatcher.SupervisionTest.Relay)
    start_supervised!(SupervisedDispatcher)

    assert :ok =
             SupervisedDispatcher.post(%{id: 1}, routing_key: :dispatcher_supervision_test_key)

    assert_receive {:handled, %Message{} = message}, 1_000
    assert JSON.decode!(IO.iodata_to_binary(message.payload)) == %{"id" => 1}
  end

  test "supervises one pumper per subscription" do
    start_supervised!(SupervisedDispatcher)

    assert {{Ming.Messaging.Pumper, :local, :dispatcher_supervision_test_sub, 1}, pid, :worker,
            [Ming.Messaging.Pumper]} =
             SupervisedDispatcher
             |> Supervisor.which_children()
             |> List.keyfind(
               {Ming.Messaging.Pumper, :local, :dispatcher_supervision_test_sub, 1},
               0
             )

    assert Process.alive?(pid)
  end

  test "supervises two gateways using the same adapter module" do
    Process.register(self(), Ming.Dispatcher.SupervisionTest.Relay)
    start_supervised!(DualGatewayDispatcher)

    children = Supervisor.which_children(DualGatewayDispatcher)

    assert {{Ming.Messaging.InMemory.Gateway, :first}, _, :supervisor, _} =
             List.keyfind(children, {Ming.Messaging.InMemory.Gateway, :first}, 0)

    assert {{Ming.Messaging.InMemory.Gateway, :second}, _, :supervisor, _} =
             List.keyfind(children, {Ming.Messaging.InMemory.Gateway, :second}, 0)

    assert :ok =
             DualGatewayDispatcher.post(%{id: 2},
               routing_key: :dispatcher_supervision_test_second
             )

    assert_receive {:handled, %Message{} = message}, 1_000
    assert JSON.decode!(IO.iodata_to_binary(message.payload)) == %{"id" => 2}
  end

  test "starts number_of_consumers pumpers per subscription" do
    start_supervised!(MultiConsumerDispatcher)

    children = Supervisor.which_children(MultiConsumerDispatcher)

    for index <- 1..3 do
      id = {Ming.Messaging.Pumper, :local, :dispatcher_supervision_test_multi_sub, index}
      assert {^id, pid, :worker, [Ming.Messaging.Pumper]} = List.keyfind(children, id, 0)
      assert Process.alive?(pid)
    end
  end

  test "competing consumers handle each message exactly once" do
    Process.register(self(), Ming.Dispatcher.SupervisionTest.Relay)
    start_supervised!(MultiConsumerDispatcher)

    assert :ok =
             MultiConsumerDispatcher.post(%{id: 4},
               routing_key: :dispatcher_supervision_test_multi
             )

    assert_receive {:handled, %Message{}}, 1_000
    refute_receive {:handled, %Message{}}, 300
  end

  test "defers and redelivers a message end to end" do
    Process.register(self(), Ming.Dispatcher.SupervisionTest.Relay)

    {:ok, _counter} =
      Agent.start_link(fn -> 0 end, name: Ming.Dispatcher.SupervisionTest.DeferCounter)

    start_supervised!(DeferDispatcher)

    assert :ok = DeferDispatcher.post(%{id: 3}, routing_key: :dispatcher_supervision_test_defer)

    assert_receive {:handled, %Message{} = message, 2}, 1_000
    assert JSON.decode!(IO.iodata_to_binary(message.payload)) == %{"id" => 3}
  end

  test "raises on a non-positive number_of_consumers" do
    assert_raise ArgumentError, ~r/:number_of_consumers/, fn ->
      BadConsumerCountDispatcher.init([])
    end
  end
end
