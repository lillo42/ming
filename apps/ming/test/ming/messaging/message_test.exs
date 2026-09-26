defmodule Ming.Messaging.MessageTest do
  use ExUnit.Case, async: true

  alias Ming.Messaging.Message

  defp message(extra \\ []) do
    [id: "id", payload: "payload", routing_key: :key, timestamp: DateTime.utc_now()]
    |> Keyword.merge(extra)
    |> then(&struct!(Message, &1))
  end

  test "enforces id, payload, routing_key and timestamp" do
    assert_raise ArgumentError, fn -> struct!(Message, []) end
  end

  test "applies CloudEvents defaults" do
    message = message()

    assert message.content_type == "text/plain"
    assert message.spec_version == "1.0"
    assert message.headers == %{}
  end

  test "accepts tracing and partitioning fields" do
    message =
      message(
        correlation_id: "corr",
        trace_parent: "00-abc-def-01",
        trace_state: %{"vendor" => "abc"},
        baggage: %{"user" => "alice"},
        partition_key: "p1",
        reply_to: "reply.key"
      )

    assert message.correlation_id == "corr"
    assert message.trace_parent == "00-abc-def-01"
    assert message.trace_state == %{"vendor" => "abc"}
    assert message.baggage == %{"user" => "alice"}
    assert message.partition_key == "p1"
    assert message.reply_to == "reply.key"
  end
end
