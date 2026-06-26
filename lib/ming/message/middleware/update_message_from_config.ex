defmodule Ming.Message.Middleware.UpdateMessageFromConfig do
  alias Ming.Context
  alias Ming.Message

  @behaviour Ming.Middleware

  @impl Ming.Middleware
  def before_handle(
        %Context{
          assigns: %{publication: publication},
          metadata: metadata,
          request: %Message{} = message
        } = context
      ) do
    headers =
      Keyword.get(publication, :default_headers, %{})
      |> Map.merge(Map.get(metadata, :headers, %{}))
      |> Map.merge(message.headers)

    message = %Message{
      message
      | baggage: extract(:baggage, message, metadata),
        content_type: extract(:content_type, message, metadata, publication),
        correlation_id: extract(:correlation_id, message, metadata),
        data_schema: extract(:data_schema, message, metadata, publication),
        headers: headers,
        source: extract(:source, message, metadata, publication),
        subject: extract(:subject, message, metadata, publication),
        trace_parent: extract(:trace_parent, message, metadata),
        trace_state: extract(:trace_state, message, metadata),
        type: extract(:trace_parent, message, metadata)
    }

    %Context{context | request: message}
  end

  def before_handle(%Context{} = context) do
    context
    |> Context.halt()
    |> Context.respond({:error, :invalid_params})
  end

  defp extract(key, message, metadata) do
    Map.get(message, key) || Map.get(metadata, key)
  end

  defp extract(key, message, metadata, publication) do
    Map.get(message, key) || Map.get(metadata, key) || Keyword.get(publication, key)
  end

  @impl Ming.Middleware
  def after_handle(context), do: context
end
