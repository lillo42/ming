defmodule Ming.Message.Middleware.EncodeRequestAsMessageTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Message
  alias Ming.Message.Middleware.EncodeRequestAsMessage

  setup do
    start_supervised!(FakeMapperAgent)
    :ok
  end

  defp context(request) do
    %Context{
      assigns: %{mapper: FakeMapper},
      metadata: %{},
      request: request,
      routing_key: :ming_produce_message,
      timeout: :infinity
    }
  end

  describe "before_handle/1" do
    test "converts a request into a message and stores the original request" do
      FakeMapperAgent.set_to_message(fn request ->
        %Message{
          id: "msg-1",
          payload: request,
          routing_key: :order_created,
          timestamp: DateTime.utc_now()
        }
      end)

      ctx = context(%{"id" => 1})
      result = EncodeRequestAsMessage.before_handle(ctx)

      assert %Message{} = result.request
      assert result.request.payload == %{"id" => 1}
      assert result.assigns.original_request == %{"id" => 1}
    end

    test "handles {:ok, message} return from mapper" do
      FakeMapperAgent.set_to_message(fn _request ->
        {:ok,
         %Message{
           id: "msg-1",
           payload: "data",
           routing_key: :order_created,
           timestamp: DateTime.utc_now()
         }}
      end)

      ctx = context(%{"id" => 1})
      result = EncodeRequestAsMessage.before_handle(ctx)

      assert %Message{} = result.request
    end

    test "returns the context when mapper returns a context" do
      halted_ctx =
        context(%{"id" => 1})
        |> Context.halt()
        |> Context.respond({:error, :custom})

      FakeMapperAgent.set_to_message(fn _request -> halted_ctx end)

      assert EncodeRequestAsMessage.before_handle(context(%{"id" => 1})) == halted_ctx
    end

    test "halts when mapper returns an error" do
      FakeMapperAgent.set_to_message(fn _request -> {:error, :bad_request} end)

      ctx = context(%{"id" => 1})
      result = EncodeRequestAsMessage.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, :bad_request}
    end

    test "halts when mapper returns an invalid response" do
      FakeMapperAgent.set_to_message(fn _request -> :unexpected end)

      ctx = context(%{"id" => 1})
      result = EncodeRequestAsMessage.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, :invalid_message_mapper_response}
    end

    test "halts when mapper is not provided" do
      ctx = %Context{
        assigns: %{},
        metadata: %{},
        request: %{"id" => 1},
        routing_key: :ming_produce_message,
        timeout: :infinity
      }

      result = EncodeRequestAsMessage.before_handle(ctx)

      assert Context.halted?(result)
      assert Context.response(result) == {:error, :message_mapper_not_provided}
    end
  end
end
