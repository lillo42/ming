defmodule Ming.Messaging.Brod.DecoderTest do
  use ExUnit.Case, async: true

  alias Ming.Messaging.Brod.Decoder
  alias Ming.Messaging.Message

  defp meta do
    %{
      topic: "reports",
      partition: 0,
      routing_key: "reports.generate",
      worker: self(),
      ack_fun: fn _offset -> :ok end
    }
  end

  defp kafka_message(headers) do
    ts = DateTime.to_unix(~U[2024-01-02 03:04:05.678Z], :millisecond)
    {:kafka_message, 42, "partition-key", "payload", :create, ts, headers}
  end

  test "decodes CloudEvents binary-mode headers onto the message" do
    headers = [
      {"ce_id", "msg-1"},
      {"ce_correlationid", "corr-1"},
      {"ce_datacontenttype", "application/json"},
      {"ce_specversion", "1.0"},
      {"ce_source", "reports-service"},
      {"ce_type", "reports.generate"},
      {"ce_subject", "report-7"},
      {"ce_dataschema", "https://example.com/schema.json"},
      {"ce_dataref", "https://example.com/data"},
      {"ce_replyto", "reports.replies"},
      {"ce_traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"},
      {"ce_tracestate", "vendor=value"},
      {"ce_baggage", "user=alice"},
      {"ce_time", "2024-05-06T07:08:09.100Z"},
      {"content_encoding", "gzip"}
    ]

    message = Decoder.to_message(kafka_message(headers), meta())

    assert %Message{
             id: "msg-1",
             correlation_id: "corr-1",
             content_type: "application/json",
             content_encoding: "gzip",
             spec_version: "1.0",
             source: "reports-service",
             type: "reports.generate",
             subject: "report-7",
             data_schema: "https://example.com/schema.json",
             data_ref: "https://example.com/data",
             reply_to: "reports.replies",
             trace_parent: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
             trace_state: %{"vendor" => "value"},
             baggage: %{"user" => "alice"},
             timestamp: ~U[2024-05-06 07:08:09.100Z],
             payload: "payload",
             routing_key: "reports.generate",
             partition_key: "partition-key"
           } = message
  end

  test "applies defaults when there are no headers" do
    message = Decoder.to_message(kafka_message([]), meta())

    assert %Message{
             content_type: "application/octet-stream",
             spec_version: "1.0",
             source: "ming",
             type: "ming",
             payload: "payload",
             routing_key: "reports.generate"
           } = message

    assert is_binary(message.id)
    assert message.timestamp == ~U[2024-01-02 03:04:05.678Z]
  end

  test "accepts nil headers and nil payload" do
    {:kafka_message, offset, key, _value, ts_type, ts, _headers} = kafka_message([])
    message = Decoder.to_message({:kafka_message, offset, key, nil, ts_type, ts, nil}, meta())

    assert message.payload == ""
    assert message.timestamp == ~U[2024-01-02 03:04:05.678Z]
  end

  test "falls back to the kafka timestamp when ce_time is invalid" do
    message = Decoder.to_message(kafka_message([{"ce_time", "not-a-date"}]), meta())

    assert message.timestamp == ~U[2024-01-02 03:04:05.678Z]
  end

  test "keeps non-CloudEvents headers and drops the ce_* ones" do
    headers = [
      {"ce_id", "msg-1"},
      {"custom", "value"}
    ]

    message = Decoder.to_message(kafka_message(headers), meta())

    assert message.headers["custom"] == "value"
    refute Map.has_key?(message.headers, "ce_id")
  end

  test "stores the settlement metadata in headers[:ming_brod]" do
    message = Decoder.to_message(kafka_message([]), meta())

    assert %{topic: "reports", partition: 0, offset: 42, worker: worker, ack_fun: ack_fun} =
             message.headers[:ming_brod]

    assert worker == self()
    assert is_function(ack_fun, 1)
  end

  test "treats empty and undefined keys as no partition key" do
    for key <- [nil, :undefined, ""] do
      {:kafka_message, offset, _key, value, ts_type, ts, headers} = kafka_message([])

      message =
        Decoder.to_message({:kafka_message, offset, key, value, ts_type, ts, headers}, meta())

      assert message.partition_key == nil
    end
  end
end
