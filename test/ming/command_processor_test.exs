defmodule Ming.CommandProcessorTest do
  use ExUnit.Case

  defmodule CommandOne do
    defstruct [:val]
  end

  defmodule CommandTwo do
    defstruct [:val]
  end

  defmodule EventOne do
    defstruct [:val]
  end

  defmodule EventTwo do
    defstruct [:val]
  end

  defmodule MyHandler do
    def handle(%CommandOne{val: val}, _ctx), do: {:ok, val}
    def handle(%CommandTwo{}, _ctx), do: :ok
    def handle(%EventOne{val: val}, _ctx), do: {:ok, val}
    def handle(%EventTwo{}, _ctx), do: :ok
    def handle(%{payload: val}, _ctx), do: {:ok, val}
  end

  defmodule RouterOne do
    use Ming.Router
    register(CommandOne, handler: MyHandler)
    register(EventOne, handler: MyHandler)
    register(:atom_key_one, handler: MyHandler)
  end

  defmodule RouterTwo do
    use Ming.Router
    register(CommandTwo, handler: MyHandler)
    register(EventTwo, handler: MyHandler)
    # Same event handled in both routers
    register(EventOne, handler: MyHandler)
    register(:atom_key_two, handler: MyHandler)
  end

  defmodule MyCommandProcessor do
    use Ming.CommandProcessor, otp_app: :ming

    router(RouterOne)
    router(RouterTwo)
  end

  defmodule MessagingCommandProcessor do
    use Ming.CommandProcessor, otp_app: :ming
  end

  setup do
    original_env = Application.get_env(:ming, Ming.CommandProcessorTest.MessagingCommandProcessor)

    on_exit(fn ->
      if is_nil(original_env) do
        Application.delete_env(:ming, Ming.CommandProcessorTest.MessagingCommandProcessor)
      else
        Application.put_env(
          :ming,
          Ming.CommandProcessorTest.MessagingCommandProcessor,
          original_env
        )
      end
    end)
  end

  describe "message router integration" do
    test "post/2 publishes a request through the messaging gateway" do
      start_supervised!(FakeProducerAgent)

      Application.put_env(:ming, Ming.CommandProcessorTest.MessagingCommandProcessor,
        gateways: [
          [
            adapter: FakeProducerGateway,
            publications: [
              [
                routing_key: :order_created,
                source: "cmd-proc-test",
                mapper: FakeCommandProcessorMapper
              ]
            ]
          ]
        ]
      )

      assert {:ok, :published} =
               MessagingCommandProcessor.post(%{"order_id" => 1}, routing_key: :order_created)

      [message] = FakeProducerAgent.messages()
      assert message.source == "cmd-proc-test"
      assert JSON.decode!(message.payload) == %{"order_id" => 1}
    end
  end

  describe "start_link/1" do
    test "boots as a supervisor and starts gateways from config" do
      Application.put_env(:ming, MessagingCommandProcessor,
        gateways: [
          [
            adapter: Ming.Gateway.InMemory,
            name: :boot_test_gateway,
            publications: [[routing_key: :boot_test_key]],
            subscriptions: [[name: :boot_test_sub, routing_key: :boot_test_key]]
          ]
        ]
      )

      pid = start_supervised!(MessagingCommandProcessor)
      assert Process.alive?(pid)

      assert [{Ming.Gateway.Supervisor, gateway_sup, :supervisor, _}] =
               Supervisor.which_children(pid)

      assert Process.alive?(gateway_sup)

      assert :ok = MessagingCommandProcessor.post(%{"order_id" => 1}, :boot_test_key)
    end
  end

  describe "send/2" do
    test "routes command to the correct router" do
      assert {:ok, 42} = MyCommandProcessor.send(%CommandOne{val: 42})
      assert :ok = MyCommandProcessor.send(%CommandTwo{})
    end

    test "routes command with routing_key in opts" do
      assert {:ok, 10} = MyCommandProcessor.send(%{payload: 10}, routing_key: :atom_key_one)
      assert {:ok, 20} = MyCommandProcessor.send(%{payload: 20}, routing_key: :atom_key_two)
    end

    test "returns unregistered for unknown command" do
      assert {:error, :unregistered_command} =
               MyCommandProcessor.send(%{__struct__: UnknownCommand})
    end

    test "returns more_than_one_handler_found when routers conflict" do
      # Note: this is actually an Event handled as a Command but if we registered the same
      # command twice it would fail similarly. We can just test send with EventOne which has two routers.
      assert {:error, :more_than_one_handler_found} = MyCommandProcessor.send(%EventOne{})
    end
  end

  describe "publish/2" do
    test "publishes event to a single router" do
      assert :ok = MyCommandProcessor.publish(%EventTwo{})
    end

    test "publishes event correctly when using an atom routing key" do
      assert {:ok, 30} = MyCommandProcessor.publish(%{payload: 30}, :atom_key_one)
      assert {:ok, 40} = MyCommandProcessor.publish(%{payload: 40}, :atom_key_two)
    end

    test "publishes event with routing_key in opts" do
      assert {:ok, 30} = MyCommandProcessor.publish(%{payload: 30}, routing_key: :atom_key_one)
      assert {:ok, 40} = MyCommandProcessor.publish(%{payload: 40}, routing_key: :atom_key_two)
    end

    test "publishes event sequentially to multiple routers by default" do
      # Both RouterOne and RouterTwo handle EventOne.
      assert [{:ok, 100}, {:ok, 100}] = MyCommandProcessor.publish(%EventOne{val: 100})
    end

    test "publishes event in parallel" do
      results = MyCommandProcessor.publish(%EventOne{val: 99}, dispatch_strategy: :parallel)
      assert length(results) == 2
      assert {:ok, 99} in results
    end
  end
end

defmodule FakeCommandProcessorMapper do
  alias Ming.Context
  alias Ming.Message

  def to_message(request, %Context{assigns: %{ming_message_publication: publication}} = context) do
    %Message{
      id: context.id,
      payload: JSON.encode!(request),
      routing_key: context.routing_key,
      timestamp: context.timestamp,
      source: Keyword.get(publication, :source)
    }
  end

  def to_request(_message, _context), do: {:ok, %{}}
end
