defmodule Ming.Message.Middleware.RequestToMessage do
  alias Ming.Context
  alias Ming.Message

  @behaviour Ming.Middleware

  @impl Ming.Middleware
  def before_handle(%Context{assigns: %{ming_mapper: mapper}, request: request} = context) do
    case mapper.to_message(request, context) do
      %Message{} = message ->
        %Context{context | request: message}
        |> Context.assign(:original_request, request)

      {:ok, %Message{} = message} ->
        %Context{context | request: message}
        |> Context.assign(:original_request, request)

      %Context{} = other_context ->
        other_context

      {:error, _reason} = reply ->
        context
        |> Context.halt()
        |> Context.respond(reply)

      _other ->
        context
        |> Context.halt()
        |> Context.respond({:error, :invalid_message_mapper_resposne})
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
