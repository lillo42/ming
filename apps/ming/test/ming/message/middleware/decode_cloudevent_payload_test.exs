defmodule Ming.Message.Middleware.DecodeCloudEventPayloadTest do
  use ExUnit.Case

  alias Ming.Context
  alias Ming.Message
  alias Ming.Message.Middleware.DecodeCloudEventPayload

  defp context(request, original_message) do
    %Context{
      assigns: %{original_message: original_message},
      metadata: %{},
      request: request,
      routing_key: :ming_consume_message,
      timeout: :infinity
    }
  end

  describe "before_handle/1" do
    test "decodes a structured CloudEvent payload" do
      original = %Message{
        id: "original",
        payload: "ignored",
        routing_key: :order_created,
        timestamp: ~U[2025-01-01T00:00:00Z],
        content_type: "application/cloudevents+json"
      }

      cloudevent = %{
        "id" => "ce-1",
        "source" => "my-app",
        "specversion" => "1.0",
        "type" => "order.created",
        "data" => %{"order_id" => 123},
        "time" => "2025-06-01T12:00:00Z",
        "baggage" => "tenant=acme",
        "tracestate" => "vendor=abc"
      }

      result = DecodeCloudEventPayload.before_handle(context(cloudevent, original))

      assert result.request == %{"order_id" => 123}
      assert result.assigns.original_message.id == "ce-1"
      assert result.assigns.original_message.source == %URI{path: "my-app"}
      assert result.assigns.original_message.type == "order.created"
      assert result.assigns.original_message.timestamp == ~U[2025-06-01T12:00:00Z]
      assert result.assigns.original_message.baggage == %{"tenant" => "acme"}
      assert result.assigns.original_message.trace_state == %{"vendor" => "abc"}
    end

    test "keeps original values when CloudEvent attributes are missing" do
      original = %Message{
        id: "original",
        payload: "ignored",
        routing_key: :order_created,
        timestamp: ~U[2025-01-01T00:00:00Z],
        type: "original.type"
      }

      cloudevent = %{
        "id" => "ce-1",
        "source" => "my-app",
        "specversion" => "1.0",
        "type" => "order.created",
        "data" => %{}
      }

      result = DecodeCloudEventPayload.before_handle(context(cloudevent, original))

      assert result.assigns.original_message.type == "order.created"
      assert result.assigns.original_message.timestamp == ~U[2025-01-01T00:00:00Z]
    end

    test "passes through non-CloudEvent maps unchanged" do
      original = %Message{
        id: "original",
        payload: "ignored",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      request = %{"plain" => "map"}
      result = DecodeCloudEventPayload.before_handle(context(request, original))

      assert result.request == request
      assert result.assigns.original_message == original
    end

    test "passes through non-map requests unchanged" do
      original = %Message{
        id: "original",
        payload: "ignored",
        routing_key: :order_created,
        timestamp: DateTime.utc_now()
      }

      result = DecodeCloudEventPayload.before_handle(context("not a map", original))

      assert result.request == "not a map"
      assert result.assigns.original_message == original
    end
  end
end
