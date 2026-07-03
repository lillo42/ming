defmodule Ming.Message.Middleware.EncodeRequestAsMessage do
  @moduledoc """
  Middleware that converts a domain request into a `%Ming.Message{}`
  using a configured mapper module.

  Expects `:mapper` in context assigns.
  """

  alias Ming.Context
  alias Ming.Message

  @behaviour Ming.Middleware

  @doc """
  Converts the current request into a `%Ming.Message{}` via the configured
  mapper and stores the original request in assigns.

  Halts with an error if the mapper returns an invalid response or is
  missing.
  """
  @impl Ming.Middleware
  def before_handle(context)

  def before_handle(%Context{assigns: %{mapper: mapper}, request: request} = context) do
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
        |> Context.respond({:error, :invalid_message_mapper_response})
    end
  end

  def before_handle(%Context{} = context) do
    context
    |> Context.halt()
    |> Context.respond({:error, :message_mapper_not_provided})
  end

  @doc """
  No-op after stage.
  """
  @impl Ming.Middleware
  def after_handle(context), do: context
end
