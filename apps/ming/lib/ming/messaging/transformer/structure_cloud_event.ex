defmodule Ming.Messaging.Transformer.StructureCloudEvent do
  @behaviour Ming.Messaging.Transformer

  alias Ming.Context
  alias Ming.Messaging.Baggage
  alias Ming.Messaging.Message
  alias Ming.Messaging.TraceState

  @impl Ming.Messaging.Transformer
  def encode(
        %Message{} = message,
        _args,
        %Context{metadata: %{ming_publication: publication}}
      ) do
    Map.get(publication, :cloud_events_mode, :binary)
    |> set_structure_json(message, publication)
  end

  @impl Ming.Messaging.Transformer
  def decode(
        message,
        _args,
        %Context{metadata: %{ming_subscription: %{cloud_events_mode: :binary}}}
      ) do
    message
  end

  def decode(
        %Message{content_type: "application/cloudevents+json"} = message,
        _args,
        %Context{}
      ) do
    JSON.decode!(message.payload)
    |> extract_structure_json(message)
  end

  def decode(
        %Message{} = message,
        _args,
        %Context{metadata: %{ming_subscription: %{cloud_events_mode: :json}}}
      ) do
    json = JSON.decode!(message.payload)

    if Map.has_key?(json, "id") and
         Map.has_key?(json, "type") and
         Map.has_key?(json, "source") and
         Map.has_key?(json, "specversion") do
      extract_structure_json(json, message)
    else
      message
    end
  end

  def decode(
        %Message{content_type: "application/json"} = message,
        _args,
        %Context{}
      ) do
    json = JSON.decode!(message.payload)

    if Map.has_key?(json, "id") and
         Map.has_key?(json, "type") and
         Map.has_key?(json, "source") and
         Map.has_key?(json, "specversion") do
      extract_structure_json(json, message)
    else
      message
    end
  end

  def decode(%Message{} = message, _args, %Context{}) do
    message
  end

  defp set_structure_json(:binary, %Message{} = messsage, _publication), do: messsage

  defp set_structure_json(:json, %Message{} = message, publication) do
    cloud_event_properites = Map.get(publication, :additional_cloud_events_properties, %{})

    payload =
      cloud_event_properites
      |> Map.merge(%{
        id: message.id,
        baggage: Baggage.to_string(message.baggage),
        correlationid: message.correlation_id,
        datacontenttype: message.content_type,
        dataschema: message.data_schema,
        dataref: message.data_ref,
        replyto: message.reply_to,
        specversion: message.spec_version,
        source: message.source,
        subject: message.subject,
        time: message.timestamp,
        traceparent: message.trace_parent,
        tracestate: TraceState.to_string(message.trace_state),
        type: message.type
      })
      |> set_data(message)
      |> JSON.encode_to_iodata!()

    %Message{message | content_type: "application/cloudevents+json", payload: payload}
  end

  defp set_data(payload, %Message{} = message) do
    value = to_binary(message.payload)

    if base64?(value) do
      Map.put(payload, :data_base64, value)
    else
      Map.put(payload, :data, value)
    end
  end

  defp to_binary(value) when is_binary(value) do
    try do
      IO.iodata_to_binary(value)
    rescue
      _ -> value
    end
  end

  defp base64?(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp extract_structure_json(json, %Message{} = message) when is_map(json) do
    %Message{
      message
      | id: Map.get(json, "id", message.id),
        baggage: Baggage.from_string(Map.get(json, "baggage", message.baggage)),
        correlation_id: Map.get(json, "correlationid", message.correlation_id),
        content_type: Map.get(json, "datacontenttype", message.content_type),
        data_schema: Map.get(json, "dataschema", message.data_schema),
        data_ref: Map.get(json, "dataref", message.data_ref),
        reply_to: Map.get(json, "replyto", message.reply_to),
        spec_version: Map.get(json, "specversion", message.spec_version),
        payload: Map.get(json, "data") || Map.get(json, "data_base64"),
        source: Map.get(json, "source", message.source),
        subject: Map.get(json, "subject", message.subject),
        timestamp: Map.get(json, "time", message.timestamp),
        trace_parent: Map.get(json, "traceparent", message.trace_parent),
        trace_state: TraceState.from_string(Map.get(json, "tracestate", message.trace_state)),
        type: Map.get(json, "type", message.type)
    }
  end
end
