if Code.ensure_loaded?(:brod) do
  defmodule Ming.Gateway.Kafka.Consumer do
    alias Ming.Message
    alias Ming.Message.Baggage
    alias Ming.Message.TraceState

    @behaviour :brod_group_subscriber_v2

    @impl :brod_group_subscriber_v2
    def init(_groupd_id, _init_data) do
      {:ok, []}
    end

    @impl :brod_group_subscriber_v2
    def handle_message(message, state) do
      offset = elem(message, 1)
      key = elem(message, 2)
      value = elem(message, 3)
      headers = elem(message, 6)

      topic = Keyword.fetch!(state, :topic)
      partition = Keyword.get(state, :partition)

      headers =
        to_ming_headers(%{}, headers)
        |> Map.put(:kafka_offset, offset)
        |> Map.put(:kafka_partition, partition)
        |> Map.put(:kafka_topic, topic)

      routing_key = Keyword.fetch!(state, :routing_key)
      command_processor = Keyword.fetch!(state, :command_processor)
      timeout = Keyword.fetch!(state, :timeout)

      message_id =
        case Map.get(headers, "ce_id") do
          nil -> UUIDv7.generate()
          "" -> ""
          id -> id
        end

      timestamp = parse_timestamp(Map.get(headers, "ce_time"))

      %Message{
        id: message_id,
        baggage: Baggage.from_string(Map.get(headers, "ce_baggage")),
        content_type: Map.get(headers, "ce_datacontenttype"),
        correlation_id: Map.get(headers, "ce_correlationid"),
        data_ref: Map.get(headers, "ce_dataref"),
        data_schema: parse_uri(Map.get(headers, "ce_dataschema")),
        headers: headers,
        partition_key: key,
        payload: value,
        reply_to: Map.get(headers, "ce_replyto"),
        routing_key: routing_key,
        spec_version: Map.get(headers, "ce_specversion", "1.0"),
        source: parse_uri(Map.get(headers, "ce_source", "https://hex.pm/packages/ming")),
        subject: Map.get(headers, "ce_subject"),
        timestamp: timestamp,
        trace_parent: Map.get(headers, "ce_traceparent"),
        trace_state: TraceState.from_string(Map.get(headers, "ce_tracestate")),
        type: Map.get(headers, "ce_type")
      }

      result =
        command_processor.send(message,
          routing_key: :ming_consume_message,
          metadata: %{routing_key: routing_key},
          timeout: timeout
        )

      case result do
        {:ok, :ack} ->
          {:ok, :ack, state}

        {:ok, :reject} ->
          {:ok, :ack, state}

        {:ok, :requeue} ->
          {:ok, state}

        {:error, _reason} ->
          {:ok, :ack, state}
      end
    end

    defp to_ming_headers(headers, []), do: headers

    defp to_ming_headers(headers, [{key, val} | next]),
      do: to_ming_headers(Map.put(headers, key, val), next)

    defp parse_timestamp(nil), do: DateTime.utc_now()
    defp parse_timestamp(:undefined), do: DateTime.utc_now()

    defp parse_timestamp(val) when is_number(val) do
      case DateTime.from_unix(val, :second) do
        {:ok, datetime} ->
          datetime

        {:error, _reason} ->
          DateTime.utc_now()
      end
    end

    defp parse_timestamp(val) when is_binary(val) do
      case DateTime.from_iso8601(val) do
        {:ok, datetime, _calendar} ->
          datetime

        {:error, _reason} ->
          DateTime.utc_now()
      end
    end

    defp parse_uri(nil), do: nil

    defp parse_uri(val) do
      case URI.new(val) do
        {:ok, uri} ->
          uri

        {:error, _reason} ->
          val
      end
    end
  end
end
