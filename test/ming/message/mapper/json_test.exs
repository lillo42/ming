defmodule Ming.Message.Mapper.JsonTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Message
  alias Ming.Message.Mapper.Json

  defp context(request, publication, metadata \\ %{}) do
    %Context{
      assigns: %{ming_message_publication: publication},
      id: "msg-1",
      correlation_id: "corr-1",
      metadata: metadata,
      request: request,
      routing_key: :order_created,
      timestamp: ~U[2025-01-01T00:00:00Z],
      timeout: :infinity
    }
  end

  describe "to_message/2" do
    test "binary mode encodes the request as JSON payload" do
      publication = [routing_key: :order_created]
      ctx = context(%{"id" => 1}, publication)

      assert %Message{} = message = Json.to_message(ctx.request, ctx)
      assert message.content_type == "application/json"
      assert message.routing_key == :order_created
      assert message.id == "msg-1"
      assert message.correlation_id == "corr-1"
      assert message.timestamp == ~U[2025-01-01T00:00:00Z]
      assert JSON.decode!(IO.iodata_to_binary(message.payload)) == %{"id" => 1}
    end

    test "json mode builds a structured CloudEvents payload" do
      publication = [
        routing_key: :order_created,
        cloudevent_mode: :json,
        source: "my-app",
        type: "order.created"
      ]

      ctx = context(%{"id" => 1}, publication, %{headers: %{"x-custom" => "value"}})

      assert %Message{} = message = Json.to_message(ctx.request, ctx)
      assert message.content_type == "application/cloudevents+json"
      assert message.headers == %{"x-custom" => "value"}

      decoded = JSON.decode!(IO.iodata_to_binary(message.payload))
      assert decoded["id"] == "msg-1"
      assert decoded["source"] == "my-app"
      assert decoded["type"] == "order.created"
      assert decoded["data"] == %{"id" => 1}
    end

    test "halts when publication is missing" do
      ctx = %Context{
        id: "msg-1",
        correlation_id: "corr-1",
        metadata: %{},
        request: %{},
        routing_key: :order_created,
        timestamp: ~U[2025-01-01T00:00:00Z],
        timeout: :infinity
      }

      assert %Context{halted?: true, response: {:error, :invalid_param}} =
               Json.to_message(ctx.request, ctx)
    end
  end

  describe "to_request/2" do
    test "decodes JSON payload into a request" do
      message = %Message{
        id: "msg-1",
        payload: JSON.encode!(%{"id" => 1}),
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      assert Json.to_request(message, nil) == {:ok, %{"id" => 1}}
    end
  end
end
