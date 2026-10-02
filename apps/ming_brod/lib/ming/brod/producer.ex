defmodule Ming.Brod.Producer do
  @behaviour Ming.Messaging.Producer

  alias Ming.Context
  alias Ming.Messaging.Baggage
  alias Ming.Messaging.Message
  alias Ming.Messaging.TraceState

  @impl Ming.Messaging.Producer
  def produce(
        %Message{} = message,
        %Context{metadata: %{ming_publication: publication}}
      ) do
    headers =
      set_cloud_events_headers(message)
      |> to_kafka_headers()

    :brod.produce(
      publication.name,
      publication.topic,
      partition(message, publication),
      message.partition_key,
      %{
        value: message.payload,
        headers: headers,
        ts: DateTime.to_unix(message.timestamp, :millisecond)
      }
    )

    :ok
  end

  defp partition(%Message{partition_key: nil}, publication),
    do: Map.get(publication, :partition_on_nil_key, :random)

  defp partition(_message, publication), do: Map.get(publication, :partition, :hash)

  defp set_cloud_events_headers(%Message{headers: headers} = message) do
    cloud_events_headers =
      %{
        ce_id: message.id,
        ce_correlationid: message.correlation_id,
        ce_datacontenttype: message.content_type,
        ce_spec_version: message.spec_version,
        ce_source: message.source,
        ce_time: message.timestamp,
        ce_type: message.type
      }
      |> put_if_not_nil(:ce_baggage, Baggage.to_string(message.baggage))
      |> put_if_not_nil(:ce_dataschema, message.data_schema)
      |> put_if_not_nil(:ce_dataref, message.data_ref)
      |> put_if_not_nil(:ce_replyto, message.reply_to)
      |> put_if_not_nil(:ce_subject, message.subject)
      |> put_if_not_nil(:ce_traceparent, message.trace_parent)
      |> put_if_not_nil(:ce_tracestate, TraceState.to_string(message.trace_state))
      |> put_if_not_nil(:content_encoding, message.content_encoding)

    Map.merge(cloud_events_headers, headers)
  end

  defp put_if_not_nil(map, _key, nil) when is_map(map), do: map
  defp put_if_not_nil(map, key, value) when is_map(map), do: Map.get(map, key, value)

  defp to_kafka_headers(headers) do
    headers
    |> Map.to_list()
    |> Enum.map(&{elem(&1, 0), to_binary(elem(&1, 1))})
  end

  defp to_binary(true), do: <<1>>
  defp to_binary(false), do: <<0>>
  defp to_binary(val) when is_binary(val), do: val
  defp to_binary(val) when is_atom(val), do: to_string(val)
  defp to_binary(val) when is_float(val), do: <<val::little-float-64>>
  defp to_binary(val) when is_integer(val), do: <<val::little-signed>>
  defp to_binary(%URI{} = val), do: URI.to_string(val)
  defp to_binary(%DateTime{} = val), do: DateTime.to_iso8601(val)
  defp to_binary(val), do: :erlang.term_to_binary(val)
end
