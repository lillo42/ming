defmodule Ming.Gateway.SupervisorTest do
  use ExUnit.Case

  alias Ming.Gateway.Supervisor

  describe "init/1" do
    test "returns a valid supervisor spec for a valid gateway config" do
      opts = [
        [
          adapter: FakeGatewayAdapter,
          name: :test_gateway,
          command_processor: FakeCommandProcessor,
          connection: [uri: "amqp://localhost"],
          exchange: [name: "events", type: :topic],
          publications: [[routing_key: :order_created]],
          subscriptions: [
            [name: :orders, topic_or_queue: "orders.queue", routing_key: :order_created]
          ]
        ]
      ]

      assert {:ok, {%{strategy: :one_for_one}, children}} = Supervisor.init(opts)
      assert length(children) == 1
    end

    test "returns an error when a publication routing key is duplicated" do
      opts = [
        [
          adapter: FakeGatewayAdapter,
          publications: [
            [routing_key: :order_created],
            [routing_key: :order_created]
          ]
        ]
      ]

      assert Supervisor.init(opts) ==
               {:error, {:duplicate_publication_routing_key, :order_created}}
    end

    test "returns an error when a subscription name is duplicated" do
      opts = [
        [
          adapter: FakeGatewayAdapter,
          subscriptions: [
            [name: :orders, topic_or_queue: "q1", routing_key: :order_created],
            [name: :orders, topic_or_queue: "q2", routing_key: :order_created]
          ]
        ]
      ]

      assert Supervisor.init(opts) == {:error, {:duplicate_subscription_name, :orders}}
    end

    test "returns an error when publication routing key is not an atom" do
      opts = [
        [
          adapter: FakeGatewayAdapter,
          publications: [[routing_key: "order_created"]]
        ]
      ]

      assert Supervisor.init(opts) ==
               {:error, {:invalid_publication_routing_key, "order_created"}}
    end

    test "returns an error when subscription name is not an atom" do
      opts = [
        [
          adapter: FakeGatewayAdapter,
          subscriptions: [[name: "orders", topic_or_queue: "q1", routing_key: :order_created]]
        ]
      ]

      assert Supervisor.init(opts) == {:error, {:invalid_subscription_name, "orders"}}
    end
  end
end

defmodule FakeGatewayAdapter do
  def provision_infrastructure(_args), do: :ok

  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [[]]}}
  end

  def start_link(_opts) do
    Agent.start_link(fn -> nil end, name: __MODULE__)
  end
end
