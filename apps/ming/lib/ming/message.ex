defmodule Ming.Message do
  @moduledoc """
  Represents a message in the Ming messaging system.

  This struct is used as the standard message format across gateways
  and supports CloudEvents attributes for interoperability.

  ## Fields

  - `:id` — Unique message identifier.
  - `:correlation_id` — Correlation identifier for tracing requests.
  - `:payload` — Raw message payload (required).
  - `:routing_key` — Destination routing key (required).
  - `:timestamp` — `%DateTime{}` when the message was created (required).
  - `:content_type` — MIME type of the payload, defaults to `"text/plain"`.
  - `:headers` — Map of protocol/gateway-specific headers, defaults to `%{}`.
  - `:spec_version` — CloudEvents spec version, defaults to `"1.0"`.
  - `:source` — CloudEvents source.
  - `:type` — CloudEvents type.
  - `:subject` — CloudEvents subject.
  - `:data_schema` — CloudEvents data schema URI.
  - `:data_ref` — CloudEvents data reference.
  - `:trace_parent` — W3C trace parent.
  - `:trace_state` — W3C trace state map.
  - `:baggage` — W3C baggage map.
  - `:reply_to` — Reply-to address or routing key.
  - `:partition_key` — Partitioning key for ordered delivery.
  - `:additional_cloud_events_properties` — Extra CloudEvent attributes.
  """

  @type t :: %__MODULE__{
          id: Ming.id(),
          baggage: map() | nil,
          content_type: String.t(),
          correlation_id: Ming.id(),
          data_schema: URI.t() | String.t() | nil,
          data_ref: URI.t() | String.t() | nil,
          headers: map(),
          partition_key: String.t() | atom() | nil,
          payload: :binary,
          reply_to: URI.t() | String.t() | nil,
          source: URI.t() | String.t(),
          spec_version: String.t(),
          subject: String.t() | nil,
          trace_parent: String.t() | nil,
          trace_state: map() | nil,
          timestamp: DateTime.t(),
          type: String.t() | atom()
        }

  @enforce_keys [:id, :payload, :routing_key, :timestamp]
  defstruct [
    :id,
    :baggage,
    :correlation_id,
    :data_schema,
    :data_ref,
    :partition_key,
    :payload,
    :reply_to,
    :routing_key,
    :source,
    :subject,
    :trace_state,
    :trace_parent,
    :timestamp,
    :type,
    content_type: "text/plain",
    headers: %{},
    spec_version: "1.0"
  ]

  @requeue_count_header "x-ming-requeue-count"

  @doc """
  Returns the name of the header used to track how many times a message
  has been requeued (`#{@requeue_count_header}`).
  """
  @spec requeue_count_header() :: String.t()
  def requeue_count_header, do: @requeue_count_header

  @doc """
  Returns how many times the message has been requeued so far, based on
  the `#{@requeue_count_header}` header. Defaults to `0` when the header
  is missing or malformed.
  """
  @spec requeue_count(t()) :: non_neg_integer()
  def requeue_count(%__MODULE__{headers: headers}) do
    case Map.get(headers, @requeue_count_header) do
      count when is_integer(count) and count >= 0 ->
        count

      count when is_binary(count) ->
        case Integer.parse(count) do
          {count, _rest} when count >= 0 -> count
          :error -> 0
        end

      _other ->
        0
    end
  end

  @doc """
  Returns a copy of the message with the requeue counter header set to
  `count`.
  """
  @spec put_requeue_count(t(), non_neg_integer()) :: t()
  def put_requeue_count(%__MODULE__{} = message, count)
      when is_integer(count) and count >= 0 do
    %__MODULE__{message | headers: Map.put(message.headers, @requeue_count_header, count)}
  end
end
