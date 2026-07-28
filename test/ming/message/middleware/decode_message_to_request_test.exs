defmodule Ming.Message.Middleware.DecodeMessageToRequestTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Ming.Context
  alias Ming.Message
  alias Ming.Message.Middleware.DecodeMessageToRequest

  setup do
    start_supervised!(FakeMapperAgent)
    :ok
  end

  defp context(message) do
    %Context{
      assigns: %{mapper: FakeMapper},
      metadata: %{},
      request: message,
      routing_key: :ming_consume_message,
      timeout: :infinity
    }
  end

  describe "before_handle/1" do
    test "decodes message into request and stores original message" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      FakeMapperAgent.set_to_request(fn msg -> {:ok, %{"payload" => msg.payload}} end)

      ctx = context(message)
      result = DecodeMessageToRequest.before_handle(ctx)

      assert result.request == %{"payload" => "data"}
      assert result.assigns.original_message == message
    end

    test "returns context when mapper returns a context" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      halted_ctx =
        context(message)
        |> Context.halt()
        |> Context.respond({:error, :custom})

      FakeMapperAgent.set_to_request(fn _msg -> halted_ctx end)

      assert DecodeMessageToRequest.before_handle(context(message)) == halted_ctx
    end

    test "halts with {:reject, :unaccepted} when mapper returns an error" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      FakeMapperAgent.set_to_request(fn _msg -> {:error, :parse_failed} end)

      ctx = context(message)

      log =
        capture_log([level: :error], fn ->
          result = DecodeMessageToRequest.before_handle(ctx)

          assert Context.halted?(result)
          assert Context.response(result) == {:reject, :unaccepted}
        end)

      assert log =~ "unacceptable message"
    end

    test "halts with {:reject, :unaccepted} when mapper raises" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      FakeMapperAgent.set_to_request(fn _msg -> raise "boom" end)

      ctx = context(message)

      log =
        capture_log([level: :error], fn ->
          result = DecodeMessageToRequest.before_handle(ctx)

          assert Context.halted?(result)
          assert Context.response(result) == {:reject, :unaccepted}
        end)

      assert log =~ "unacceptable message"
    end

    test "uses raw return value as request" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      FakeMapperAgent.set_to_request(fn _msg -> %{"raw" => true} end)

      ctx = context(message)
      result = DecodeMessageToRequest.before_handle(ctx)

      assert result.request == %{"raw" => true}
      assert result.assigns.original_message == message
    end

    test "falls back to metadata default_message_mapper when mapper is not assigned" do
      message = %Message{
        id: "msg-1",
        payload: "data",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      FakeMapperAgent.set_to_request(fn msg -> {:ok, %{"payload" => msg.payload}} end)

      ctx = %Context{
        assigns: %{},
        metadata: %{default_message_mapper: FakeMapper},
        request: message,
        routing_key: :ming_consume_message,
        timeout: :infinity
      }

      result = DecodeMessageToRequest.before_handle(ctx)

      assert result.request == %{"payload" => "data"}
      assert result.assigns.original_message == message
    end

    test "falls back to the default JSON mapper when no mapper is configured" do
      message = %Message{
        id: "msg-1",
        payload: ~s({"a": 1}),
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      ctx = %Context{
        assigns: %{},
        metadata: %{},
        request: message,
        routing_key: :ming_consume_message,
        timeout: :infinity
      }

      result = DecodeMessageToRequest.before_handle(ctx)

      assert result.request == %{"a" => 1}
      assert result.assigns.original_message == message
    end
  end
end
