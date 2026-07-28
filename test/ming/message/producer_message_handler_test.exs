defmodule Ming.Message.ProducerMessageHandlerTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Message
  alias Ming.Message.ProducerMessageHandler

  setup do
    start_supervised!(FakeProducerAgent)
    start_supervised!(FakeCommandProcessorAgent)
    :ok
  end

  describe "handle/2 for :ming_produce_message" do
    test "publishes the message through the gateway producer" do
      ctx = %Context{
        routing_key: :ming_produce_message,
        assigns: %{
          gateway: [adapter: FakeProducerGateway],
          publication: [routing_key: :order_created]
        },
        metadata: %{producer_opts: [persistent: true]},
        request: %Message{
          id: "msg-1",
          payload: "data",
          routing_key: :order_created,
          timestamp: DateTime.utc_now()
        },
        timeout: :infinity
      }

      assert ProducerMessageHandler.handle(ctx.request, ctx) == :published
      assert FakeProducerAgent.messages() == [ctx.request]
    end
  end

  describe "handle/2 for :ming_consume_message" do
    test "returns :ack when command processor returns :ok" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> :ok end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == :ack
    end

    test "returns :ack when command processor returns {:ok, response}" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> {:ok, %{}} end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == :ack
    end

    test "returns :ack when command processor returns :ack" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> :ack end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == :ack
    end

    test "returns :reject when command processor returns :reject" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> :reject end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == :reject
    end

    test "returns :requeue when command processor returns :requeue" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> :requeue end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == :requeue
    end

    test "unwraps ack/reject/requeue wrapped in {:ok, _} by the dispatch pipeline" do
      for {response, expected} <- [ack: :ack, reject: :reject, requeue: :requeue] do
        FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> {:ok, response} end)
        ctx = consume_context()
        assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == expected
      end
    end

    test "passes through {:reject, reason} from the command processor" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> {:reject, :unaccepted} end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == {:reject, :unaccepted}
    end

    test "unwraps {:reject, reason} wrapped in {:ok, _} by the dispatch pipeline" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts ->
        {:ok, {:reject, :unaccepted}}
      end)

      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == {:reject, :unaccepted}
    end

    test "returns :reject when command processor returns an error" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> {:error, :failed} end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == :reject
    end

    test "returns :requeue when command processor raises" do
      FakeCommandProcessorAgent.set_behavior(fn _request, _opts -> raise "boom" end)
      ctx = consume_context()
      assert ProducerMessageHandler.handle(%{"id" => 1}, ctx) == :requeue
    end
  end

  defp consume_context do
    %Context{
      routing_key: :ming_consume_message,
      assigns: %{},
      metadata: %{
        routing_key: :order_created,
        command_process: FakeCommandProcessor
      },
      request: %{"id" => 1},
      timeout: :infinity
    }
  end
end
