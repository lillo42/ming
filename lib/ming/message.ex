defmodule Ming.Message do
  @moduledoc """
  Represents a message in the Ming messaging system.

  This struct is used as the standard message format across gateways
  and supports CloudEvents attributes for interoperability.
  """

  @type t :: %__MODULE__{
          id: Ming.id(),
          additional_cloud_events_properties: map() | nil,
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

  @enforce_keys [:id, :payload, :routing_key]
  defstruct [
    :id,
    :additional_cloud_events_properties,
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

  def new(attrs \\ %{}) do
    struct!(__MODULE__, Map.put_new(attrs, :timestamp, DateTime.utc_now()))
  end
end
