defmodule Ming.Messaging.Brod.Decoder do
  @moduledoc """
  Decodes a Kafka message into a `%Ming.Messaging.Message{}`.

  Reads the CloudEvents binary-mode headers (`ce_*`) written by
  `Ming.Messaging.Brod.Producer` back onto the message fields. Headers
  that are not CloudEvents attributes are kept in `:headers` as
  `{binary, binary}` entries — the typed encoding the producer applies
  (little-endian integers, booleans as `<<1>>`/`<<0>>`, ...) is not
  inverted for user headers, since the original type cannot be recovered
  from the wire bytes.

  The Kafka coordinates needed to settle the message (`:topic`,
  `:partition`, `:offset`, the subscriber `:worker` pid and the offset
  `:ack_fun`) are stored in `headers[:ming_brod]` and consumed by
  `Ming.Messaging.Brod.Consumer.ack/2`.
  """

  alias Ming.Messaging.Baggage
  alias Ming.Messaging.Message
  alias Ming.Messaging.TraceState

  @cloud_event_headers [
    "ce_id",
    "ce_correlationid",
    "ce_datacontenttype",
    "ce_dataschema",
    "ce_dataref",
    "ce_replyto",
    "ce_source",
    "ce_specversion",
    "ce_subject",
    "ce_time",
    "ce_type",
    "ce_baggage",
    "ce_traceparent",
    "ce_tracestate",
    "content_encoding"
  ]

  @doc """
  Builds a `%Ming.Messaging.Message{}` from a `:brod` message record and
  the settlement metadata from the subscriber worker.
  """
  def to_message({:kafka_message, offset, key, value, _ts_type, ts, kafka_headers}, meta) do
    headers = Map.new(kafka_headers || [])

    %Message{
      id: Map.get(headers, "ce_id") || UUIDv7.generate(),
      correlation_id: Map.get(headers, "ce_correlationid"),
      content_type: Map.get(headers, "ce_datacontenttype", "application/octet-stream"),
      content_encoding: Map.get(headers, "content_encoding"),
      spec_version: Map.get(headers, "ce_specversion", "1.0"),
      source: Map.get(headers, "ce_source", "ming"),
      type: Map.get(headers, "ce_type", "ming"),
      subject: Map.get(headers, "ce_subject"),
      data_schema: Map.get(headers, "ce_dataschema"),
      data_ref: Map.get(headers, "ce_dataref"),
      reply_to: Map.get(headers, "ce_replyto"),
      trace_parent: Map.get(headers, "ce_traceparent"),
      trace_state: headers |> Map.get("ce_tracestate") |> TraceState.from_string(),
      baggage: headers |> Map.get("ce_baggage") |> Baggage.from_string(),
      payload: value || "",
      routing_key: Map.fetch!(meta, :routing_key),
      timestamp: timestamp(Map.get(headers, "ce_time"), ts),
      partition_key: partition_key(key),
      headers: user_headers(headers, offset, meta)
    }
  end

  defp timestamp(nil, ts), do: to_datetime(ts)

  defp timestamp(iso8601, ts) when is_binary(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, datetime, _offset} -> datetime
      {:error, _reason} -> to_datetime(ts)
    end
  end

  defp to_datetime(nil), do: DateTime.utc_now()
  defp to_datetime(:undefined), do: DateTime.utc_now()
  defp to_datetime(ms), do: DateTime.from_unix!(ms, :millisecond)

  defp partition_key(nil), do: nil
  defp partition_key(:undefined), do: nil
  defp partition_key(""), do: nil
  defp partition_key(key), do: key

  defp user_headers(headers, offset, meta) do
    headers
    |> Map.drop(@cloud_event_headers)
    |> Map.put(:ming_brod, %{
      topic: Map.fetch!(meta, :topic),
      partition: Map.fetch!(meta, :partition),
      offset: offset,
      worker: Map.fetch!(meta, :worker),
      ack_fun: Map.fetch!(meta, :ack_fun)
    })
  end
end
