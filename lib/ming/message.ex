defmodule Ming.Message do
  @type t :: %{}

  @enforce_keys [:id, :payload, :routing_key]
  defstruct [
    :id,
    :additional_cloud_events_properties,
    :baggage,
    :correlation_id,
    :data_schema,
    :data_ref,
    :headers,
    :partition_key,
    :payload,
    :reply_to,
    :routing_key,
    :source,
    :subject,
    :trace_state,
    :trace_parent,
    :type,
    content_type: "text/plain",
    spec_version: "1.0",
    timestamp: DateTime.utc_now()
  ]
end
