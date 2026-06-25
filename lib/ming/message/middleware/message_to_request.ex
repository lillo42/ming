defmodule Ming.Message.Middleware.MessageToRequest do
  alias Ming.Context

  @behaviour Ming.Middleware

  @impl Ming.Middleware
  def before_handle(%Context{assigns: %{ming_mapper: mapper}, request: message} = context) do
    case mapper.to_request(message, context) do
      {:ok, request} ->
        %Context{context | request: request}
        |> Context.assign(:original_message, message)

      %Context{} = other_context ->
        other_context

      {:error, _reason} = reply ->
        context
        |> Context.halt()
        |> Context.respond(reply)

      request ->
        %Context{context | request: request}
        |> Context.assign(:original_message, message)
    end
  end

  def before_handle(%Context{} = context) do
    context
    |> Context.halt()
    |> Context.respond({:error, :message_mapper_not_provided})
  end

  @impl Ming.Middleware
  def after_handle(context), do: context
end
