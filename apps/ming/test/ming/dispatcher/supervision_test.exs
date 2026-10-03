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

    assert {{Ming.Messaging.Pumper, :local, :dispatcher_supervision_test_sub}, pid, :worker,
            [Ming.Messaging.Pumper]} =
             SupervisedDispatcher
             |> Supervisor.which_children()
             |> List.keyfind({Ming.Messaging.Pumper, :local, :dispatcher_supervision_test_sub}, 0)

    assert Process.alive?(pid)
  end
end
