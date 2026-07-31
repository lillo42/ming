defmodule Ming.Gateway.KafkaEx.Consumer do
  @moduledoc """
  `KafkaEx.Consumer.GenConsumer` implementation that consumes messages from a
  Kafka topic and dispatches them into the Ming pipeline.

  Incoming messages are parsed into `%Ming.Message{}` structs with
  CloudEvents (`ce_` prefixed headers) and W3C trace context support.

  Messages are delivered in batches; each record is processed individually
  and the batch offset is committed asynchronously once the whole batch has
  been handled.

  Handler results map to offsets: `:ack` commits. `:reject` commits after
  forwarding the message to the publication named by the subscription's
  `:dead_letter_queue_routing_key` option when configured (Kafka has no
  reject). `:requeue` commits after republishing to the publication named
  by the subscription's `:requeue_routing_key` option when configured
  (Kafka has no requeue) — without one, an error is logged and the message
  is simply acked. `{:reject, :unaccepted}` (also produced when a message
  fails to decode) commits after forwarding to the publication named by
  `:invalid_message_routing_key`, falling back to
  `:dead_letter_queue_routing_key`.
  """

  use KafkaEx.Consumer.GenConsumer

  require Logger

  alias KafkaEx.Messages.Fetch.Record
  alias KafkaEx.Messages.Header
  alias Ming.Message
  alias Ming.Message.Baggage
  alias Ming.Message.TraceState

  @impl KafkaEx.Consumer.GenConsumer
  def init(topic, partition, extra_args) do
    {:ok,
     %{
       topic: topic,
       partition: partition,
       routing_key: Map.fetch!(extra_args, :routing_key),
       command_processor: Map.fetch!(extra_args, :command_processor),
       timeout: Map.get(extra_args, :timeout, :infinity),
       requeue_routing_key: Map.get(extra_args, :requeue_routing_key),
       dead_letter_queue_routing_key: Map.get(extra_args, :dead_letter_queue_routing_key),
       invalid_message_routing_key: Map.get(extra_args, :invalid_message_routing_key)
     }}
  end

  @impl KafkaEx.Consumer.GenConsumer
  def handle_message_set(message_set, state) do
    Enum.each(message_set, &handle_record(&1, state))

    {:async_commit, state}
  end

  defp handle_record(%Record{} = record, state) do
    command_processor = state.command_processor
    message = to_message(record, state)

    result =
      command_processor.send(message,
        routing_key: :ming_consume_message,
        metadata: %{routing_key: state.routing_key, command_process: command_processor},
        timeout: state.timeout
      )

    case result do
      {:ok, :ack} ->
        :ok

      {:ok, {:reject, :unaccepted}} ->
        handle_unaccepted(message, state)

      {:reject, :unaccepted} ->
        handle_unaccepted(message, state)

      {:ok, :reject} ->
        forward_dead_letter(message, state)

      {:ok, {:reject, _reason}} ->
        forward_dead_letter(message, state)

      {:reject, _reason} ->
        forward_dead_letter(message, state)

      {:ok, :requeue} ->
        # Kafka has no requeue; republish to the configured requeue
        # topic when present, otherwise log and ack
        if requeue = state.requeue_routing_key do
          command_processor.post(message, requeue)
        else
          Logger.error(
            "Kafka does not support requeue; the message was acked and will not be redelivered",
            message_id: message.id,
            routing_key: state.routing_key,
            kafka_topic: state.topic,
            kafka_partition: state.partition
          )
        end

      {:error, _reason} ->
        :ok
    end
  end

  # Unacceptable (poison) message: forward to the invalid message
  # channel when configured, falling back to the dead letter queue,
  # then ack
  defp handle_unaccepted(message, state) do
    forward_to = state.invalid_message_routing_key || state.dead_letter_queue_routing_key

    if forward_to do
      state.command_processor.post(enrich_headers(message, state), forward_to)
    else
      Logger.error(
        "unacceptable message and no invalid message or dead letter queue configured; the message was acked and will not be redelivered",
        message_id: message.id,
        routing_key: state.routing_key,
        kafka_topic: state.topic,
        kafka_partition: state.partition
      )
    end
  end

  # Kafka has no reject; forwards to the dead letter queue when
  # configured, otherwise the message is simply skipped on ack
  defp forward_dead_letter(message, state) do
    if dead_letter_queue = state.dead_letter_queue_routing_key do
      state.command_processor.post(enrich_headers(message, state), dead_letter_queue)
    else
      Logger.error(
        "rejected message and no dead letter queue configured; the message was acked and will not be redelivered",
        message_id: message.id,
        routing_key: state.routing_key,
        kafka_topic: state.topic,
        kafka_partition: state.partition
      )
    end
  end

  defp enrich_headers(%Message{} = message, state) do
    headers =
      message.headers
      |> Map.put("ORIGINAL_TIMESTAMP", message.timestamp)
      |> Map.put("ORIGINAL_TOPIC", state.topic)
      |> Map.put("ORIGINAL_TYPE", message.type)

    %Message{message | headers: headers}
  end

  @doc """
  Converts a `KafkaEx.Messages.Fetch.Record` into a `%Ming.Message{}`.

  CloudEvents attributes are extracted from `ce_` prefixed Kafka headers
  when present.
  """
  @spec to_message(Record.t(), map()) :: Message.t()
  def to_message(%Record{} = record, state) do
    headers =
      record.headers
      |> List.wrap()
      |> Map.new(fn %Header{key: key, value: value} -> {key, value} end)
      |> Map.put(:kafka_offset, record.offset)
      |> Map.put(:kafka_partition, state.partition)
      |> Map.put(:kafka_topic, state.topic)

    message_id =
      case Map.get(headers, "ce_id") do
        nil -> UUIDv7.generate()
        "" -> ""
        id -> id
      end

    %Message{
      id: message_id,
      baggage: Baggage.from_string(Map.get(headers, "ce_baggage")),
      content_type: Map.get(headers, "ce_datacontenttype", "text/plain"),
      correlation_id: Map.get(headers, "ce_correlationid"),
      data_ref: Map.get(headers, "ce_dataref"),
      data_schema: parse_uri(Map.get(headers, "ce_dataschema")),
      headers: headers,
      partition_key: record.key,
      payload: record.value,
      reply_to: Map.get(headers, "ce_replyto"),
      routing_key: state.routing_key,
      spec_version: Map.get(headers, "ce_specversion", "1.0"),
      source: parse_uri(Map.get(headers, "ce_source", "https://hex.pm/packages/ming")),
      subject: Map.get(headers, "ce_subject"),
      timestamp: parse_timestamp(Map.get(headers, "ce_time"), record.timestamp),
      trace_parent: Map.get(headers, "ce_traceparent"),
      trace_state: TraceState.from_string(Map.get(headers, "ce_tracestate")),
      type: Map.get(headers, "ce_type")
    }
  end

  # CloudEvents `ce_time` header (ISO8601) takes precedence over the
  # Kafka record timestamp (unix milliseconds).
  defp parse_timestamp(nil, ts), do: parse_kafka_ts(ts)
  defp parse_timestamp("", ts), do: parse_kafka_ts(ts)

  defp parse_timestamp(val, _ts) when is_binary(val) do
    case DateTime.from_iso8601(val) do
      {:ok, datetime, _calendar} ->
        datetime

      {:error, _reason} ->
        DateTime.utc_now()
    end
  end

  defp parse_kafka_ts(nil), do: DateTime.utc_now()

  defp parse_kafka_ts(val) when is_integer(val) do
    case DateTime.from_unix(val, :millisecond) do
      {:ok, datetime} ->
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
