defmodule Ming.Message.Middleware.DecodeCloudEventPayload do
  @moduledoc """
  Middleware that decodes a structured (JSON) CloudEvents payload.

  The incoming `request` is expected to be a map representing a CloudEvent
  in structured format, i.e. a JSON object containing at least `id`,
  `source`, `specversion`, `type`, and `data`. The `data` field becomes the
  new request, while the CloudEvent metadata is merged into the original
  `%Ming.Message{}` stored in context assigns.

  Binary-mode CloudEvents (attributes transported in protocol headers) are
  intentionally not handled here. Each gateway normalizes protocol-specific
  headers into `%Ming.Message{}` fields before the message reaches this
  middleware.
  """

  alias Ming.Context
  alias Ming.Message
  alias Ming.Message.Baggage
  alias Ming.Message.TraceState

  @behaviour Ming.Middleware

  @cloudevent_required ~w(id source specversion type)

  @doc """
  Decodes a structured CloudEvents JSON payload when present.

  The `data` field becomes the new request and CloudEvent attributes are
  merged into the original `%Ming.Message{}`. Non-map requests pass through
  unchanged.
  """
  @impl Ming.Middleware
  def before_handle(
        %Context{
          assigns: %{original_message: %Message{} = message},
          request: request
        } = context
      )
      when is_map(request) do
    if structured_cloudevent?(request) do
      %Context{context | request: Map.fetch!(request, "data")}
      |> Context.assign(:original_message, update_message_from_map(message, request))
    else
      context
    end
  end

  def before_handle(context), do: context

  @doc """
  No-op after stage.
  """
  @impl Ming.Middleware
  def after_handle(context), do: context

  defp structured_cloudevent?(request) do
    Enum.all?(@cloudevent_required, &Map.has_key?(request, &1)) and
      Map.has_key?(request, "data")
  end

  defp update_message_from_map(%Message{} = message, map) do
    %Message{
      message
      | id: Map.get(map, "id") || message.id,
        source: parse_uri(Map.get(map, "source")) || message.source,
        spec_version: Map.get(map, "specversion") || message.spec_version,
        type: Map.get(map, "type") || message.type,
        content_type: Map.get(map, "datacontenttype") || message.content_type,
        data_schema: parse_uri(Map.get(map, "dataschema")) || message.data_schema,
        subject: Map.get(map, "subject") || message.subject,
        timestamp: parse_timestamp(Map.get(map, "time")) || message.timestamp,
        baggage: Baggage.from_string(Map.get(map, "baggage")),
        trace_parent: Map.get(map, "traceparent") || message.trace_parent,
        trace_state: TraceState.from_string(Map.get(map, "tracestate")),
        reply_to: Map.get(map, "replyto") || message.reply_to
    }
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

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datatime, _calendar} ->
        datatime

      {:error, _reason} ->
        nil
    end
  end
end
