defmodule Ming.Gateway.KafkaEx.Producer do
  @moduledoc """
  Implementation of `Ming.Message.Producer` for the Kafka gateway.

  Converts `%Ming.Message{}` structs into Kafka produce requests via
  `KafkaEx`. Supports CloudEvents headers in both `:binary` and `:json`
  modes.
  """

  alias Elixir.KafkaEx.API, as: KafkaExAPI
  alias Elixir.KafkaEx.Messages.Header
  alias Ming.Gateway.KafkaEx
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

    client = gateway |> Keyword.fetch!(:name) |> KafkaEx.client_name()
    topic = publication |> Keyword.fetch!(:topic_or_queue) |> to_string()

    # nil lets the KafkaEx partitioner decide: murmur2 hash on the key
    # when present, a random partition otherwise
    partition = kafka_partition(Keyword.get(extra_opts, :partition))

    produce_message =
      %{
        value: IO.iodata_to_binary(message.payload),
        timestamp: DateTime.to_unix(message.timestamp, :millisecond),
        headers: headers(publication, message)
      }
      |> put_key(message)

    try do
      case KafkaExAPI.produce(client, topic, partition, [produce_message]) do
        {:ok, _metadata} -> :ok
        {:error, reason} -> {:error, reason}
      end
    catch
      # e.g. network failures surface as GenServer exits
      :exit, reason -> {:error, reason}
    end
  end

  defp kafka_partition(partition) when is_integer(partition), do: partition
  defp kafka_partition(_partition), do: nil

  defp put_key(produce_message, %Message{partition_key: nil}), do: produce_message

  defp put_key(produce_message, %Message{partition_key: key}) when is_atom(key),
    do: Map.put(produce_message, :key, to_string(key))

  defp put_key(produce_message, %Message{partition_key: key}),
    do: Map.put(produce_message, :key, key)

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
    |> Enum.map(&to_kafka_header(&1))
  end

  defp do_headers(:json, default_headers, %Message{headers: headers}) do
    default_headers
    |> Map.merge(headers)
    |> Map.to_list()
    |> Enum.map(&to_kafka_header(&1))
  end

  defp to_kafka_header({key, %DateTime{} = val}),
    do: Header.new(to_string(key), DateTime.to_iso8601(val))

  defp to_kafka_header({key, %Duration{} = val}),
    do: Header.new(to_string(key), Duration.to_iso8601(val))

  defp to_kafka_header({key, nil}), do: Header.new(to_string(key), <<>>)
  defp to_kafka_header({key, val}) when is_binary(val), do: Header.new(to_string(key), val)
  defp to_kafka_header({key, val}), do: Header.new(to_string(key), to_string(val))

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, ""), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)
end
