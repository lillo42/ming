if Code.loaded?(Jason) do
  defmodule Ming.Message.Mapper.Jason do
    alias Ming.Context
    alias Ming.Message
    alias Ming.Message.Baggage
    alias Ming.Message.TraceState

    @behaviour Ming.Message.Mapper

    @impl Ming.Message.Mapper
    def to_message(request, %Context{assigns: %{ming_message_publication: publication}} = context) do
      mode = Keyword.get(publication, :cloudevent_mode, :binary)
      create_message(mode, request, context)
    end

    def to_message(_request, %Context{} = context) do
      context
      |> Context.halt()
      |> Context.respond({:error, :invalid_param})
    end

    defp create_message(
           :binary,
           request,
           %Context{
             correlation_id: correlation_id,
             id: id,
             routing_key: routing_key,
             timestamp: timestamp
           }
         ) do
      %Message{
        id: id,
        correlation_id: correlation_id,
        content_type: "application/json",
        payload: Jason.encode_to_iodata!(request),
        routing_key: routing_key,
        timestamp: timestamp
      }
    end

    defp create_message(
           :json,
           request,
           %Context{
             assigns: %{ming_message_publication: publication},
             metadata: metadata,
             routing_key: routing_key
           } = context
         ) do
      headers =
        Keyword.get(publication, :default_headers, %{})
        |> Map.merge(Map.get(metadata, :headers, %{}))

      payload =
        Keyword.get(publication, :additional_cloudevent_properties, %{})
        |> Map.merge(%{
          "id" => context.id,
          "source" => extract(:source, metadata, publication, "ming"),
          "specversion" => extract(:source, metadata, publication, "1.0"),
          "type" => extract(:type, metadata, publication, routing_key),
          "data" => request,
          # not mandatory
          "datacontenttype" => "application/json",
          "dataschema" => extract(:data_schema, metadata, publication),
          "subject" => extract(:subject, metadata, publication),
          "time" => context.timestamp,

          # extract field
          "baggage" => Baggage.to_string(extract(:baggage, metadata, publication)),
          "traceparent" => extract(:trace_parent, metadata, publication),
          "tracestate" => TraceState.to_string(extract(:trace_state, metadata, publication)),
          "replyto" => extract(:reply_to, metadata, publication)
        })

      %Message{
        id: context.id,
        headers: headers,
        content_type: "application/cloudevents+json",
        payload: Jason.encode_to_iodata!(payload),
        routing_key: routing_key,
        timestamp: context.timestamp
      }
    end

    defp extract(key, metadata, publication, default \\ nil) do
      Map.get(metadata, key) || Keyword.get(publication, key, default)
    end

    @impl Ming.Message.Mapper
    def to_request(%Message{} = message, _context) do
      JSON.decode(message.payload)
    end
  end
end
