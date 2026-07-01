defmodule Ming.Message.RouterTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Message

  setup do
    original_env = Application.get_env(:ming, :gateways)

    on_exit(fn ->
      if is_nil(original_env) do
        Application.delete_env(:ming, :gateways)
      else
        Application.put_env(:ming, :gateways, original_env)
      end
    end)
  end

  describe "routing keys" do
    test "exposes the messaging routing keys" do
      assert :ming_produce_message in Ming.Message.Router.__register_routing_keys__()
      assert :ming_consume_message in Ming.Message.Router.__register_routing_keys__()
    end
  end

  describe ":ming_produce_message" do
    test "produces a message through the configured gateway producer" do
      start_supervised!(FakeProducerAgent)

      Application.put_env(:ming, :gateways, [
        [
          adapter: FakeRouterGateway,
          publications: [
            [
              routing_key: :order_created,
              source: "router-test",
              type: "order.created",
              mapper: FakeRouterMapper
            ]
          ]
        ]
      ])

      assert {:ok, :published} =
               Ming.Message.Router.send(
                 :ming_produce_message,
                 %{"order_id" => 1},
                 metadata: %{
                   message_routing_key: :order_created,
                   default_message_mapper: Ming.Message.Mapper.Json
                 }
               )

      [message] = FakeProducerAgent.messages()
      assert %Message{} = message
      assert message.source == "router-test"
      assert message.type == "order.created"
      assert JSON.decode!(message.payload) == %{"order_id" => 1}
    end
  end

  describe ":ming_consume_message" do
    test "is registered as a routing key" do
      assert :ming_consume_message in Ming.Message.Router.__register_routing_keys__()
    end
  end
end

defmodule FakeRouterGateway do
  def producer, do: FakeProducer
end

defmodule FakeRouterMapper do
  alias Ming.Context
  alias Ming.Message

  def to_message(request, %Context{assigns: %{ming_message_publication: publication}} = context) do
    %Message{
      id: context.id,
      payload: JSON.encode!(request),
      routing_key: context.routing_key,
      timestamp: context.timestamp,
      source: Keyword.get(publication, :source),
      type: Keyword.get(publication, :type)
    }
  end

  def to_request(_message, _context), do: {:ok, %{}}
end
