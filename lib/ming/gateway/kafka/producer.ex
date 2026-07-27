if Code.ensure_loaded?(:brod) do
  defmodule Ming.Gateway.Kafka.Producer do
    @moduledoc """
    Implementation of `Ming.Message.Producer` for the Kafka gateway.

    Converts `%Ming.Message{}` structs into Kafka produce requests via
    `:brod`. Supports CloudEvents headers in both `:binary` and `:json`
    modes.
    """

    alias Ming.Message
    alias Ming.Message.Baggage
    alias Ming.Message.TraceState

    @behaviour Ming.Message.Producer

    @doc """
    Publishes a single `%Ming.Message{}` or a list of messages through the
    Kafka gateway.

    Options must include `:gateway` and `:publication`.
    """
    @impl Ming.Message.Producer
    def publish(message_or_messages, opts)

    def publish(messages, opts) when is_list(messages),
      do: Enum.map(messages, &publish(&1, opts))

    def publish(%Message{} = message, opts) do
      gateway = Keyword.fetch!(opts, :gateway)
      publication = Keyword.fetch!(opts, :publication)
      extra_opts = Keyword.get(opts, :extra_opts, [])

      gateway_name = Keyword.fetch!(gateway, :name)
      topic = Keyword.fetch!(publication, :topic_or_queue)

      kafka_key = kafka_key(message)
      default_partition = if is_nil(kafka_key), do: :random, else: :hash
      partition = Keyword.get(extra_opts, :partition, default_partition)

      headers = headers(publication, message)

      :brod.produce_sync(gateway_name, topic, partition, kafka_key, %{
        value: message.payload,
        headers: headers
      })
    end

    defp kafka_key(%Message{partition_key: nil}), do: <<>>
    defp kafka_key(%Message{partition_key: key}) when is_atom(key), do: to_string(key)
    defp kafka_key(%Message{partition_key: key}), do: key

    defp headers(publication, message) do
      mode = Keyword.get(publication, :cloudevent_mode, :binary)
      default_headers = Keyword.get(publication, :default_headers, %{})
      do_headers(mode, default_headers, message)
    end

    defp do_headers(:binary, default_headers, %Message{headers: headers} = message) do
      default_headers
      |> Map.merge(headers)
      |> put_if_present("ce_id", message.id)
      |> put_if_present("ce_baggage", Baggage.to_string(message.baggage))
      |> put_if_present("ce_correlationid", message.correlation_id)
      |> put_if_present("ce_dataref", message.data_ref)
      |> put_if_present("ce_datacontenttype", message.content_type)
      |> put_if_present("ce_dataschema", message.data_schema)
      |> put_if_present("ce_specversion", message.spec_version)
      |> put_if_present("ce_replyto", message.reply_to)
      |> put_if_present("ce_source", message.source)
      |> put_if_present("ce_subject", message.subject)
      |> put_if_present("ce_time", DateTime.to_iso8601(message.timestamp))
      |> put_if_present("ce_traceparent", message.trace_parent)
      |> put_if_present("ce_tracestate", TraceState.to_string(message.trace_state))
      |> put_if_present("ce_type", message.type)
      |> Map.to_list()
      |> Enum.map(&to_kafka_headers(&1))
    end

    defp do_headers(:json, default_headers, %Message{headers: headers}) do
      default_headers
      |> Map.merge(headers)
      |> Map.to_list()
      |> Enum.map(&to_kafka_headers(&1))
    end

    defp to_kafka_headers({key, %DateTime{} = val}),
      do: {to_string(key), DateTime.to_iso8601(val)}

    defp to_kafka_headers({key, %Duration{} = val}),
      do: {to_string(key), Duration.to_iso8601(val)}

    defp to_kafka_headers({key, nil}), do: {to_string(key), <<>>}
    defp to_kafka_headers({key, val}) when is_binary(val), do: {to_string(key), val}
    defp to_kafka_headers({key, val}), do: {to_string(key), to_string(val)}

    defp put_if_present(map, _key, nil), do: map
    defp put_if_present(map, _key, ""), do: map
    defp put_if_present(map, key, val), do: Map.put(map, key, val)
  end
end
