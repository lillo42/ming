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
end
