defmodule Ming.Message.Middleware.ExtractFromCloudevent do
  alias Ming.Context
  alias Ming.Message

  @behaviour Ming.Middleware

  @impl Ming.Middleware
  def before_handle(
        %Context{
          assigns: %{original_message: %Message{} = message},
          request: request
        } = context
      )
      when is_map(request) do
    if Map.has_key?(request, "id") and
         Map.has_key?(request, "source") and
         Map.has_key?(request, "specversion") and
         Map.has_key?(request, "type") and
         Map.has_key?(request, "data") do
      %Context{context | request: Map.fetch!(request, "data")}
      |> Context.assign(:original_message, %Message{
        message
        | id: Map.fetch!(request, "id"),
          source: parse_uri(Map.fetch!(request, "source")),
          spec_version: Map.fetch!(request, "specversion"),
          type: Map.fetch!(request, "type"),
          content_type: Map.get(request, "datacontenttype"),
          data_schema: parse_uri(Map.get(request, "dataschema")),
          subject: Map.get(request, "subject"),
          timestamp: parse_timestamp(Map.get(request, "time"))
      })
    else
      context
    end
  end

  def before_handle(context), do: context

  defp parse_uri(nil), do: nil

  defp parse_uri(val) do
    case URI.new(val) do
      {:ok, uri} ->
        uri

      {:error, _reason} ->
        val
    end
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()

  defp parse_timestamp(time) do
    case DateTime.from_iso8601(time) do
      {:ok, datatime, _calendar} ->
        datatime

      {:error, _reason} ->
        DateTime.utc_now()
    end
  end

  @impl Ming.Middleware
  def after_handle(context), do: context
end
