defmodule Ming.Message.Middleware.DecodeMessageToRequest do
  @moduledoc """
  Middleware that converts a `%Ming.Message{}` back to a domain request
  using a configured mapper module.

  Expects `:mapper` in context assigns.
  """

  alias Ming.Context

  @behaviour Ming.Middleware

  @doc """
  Decodes the current `%Ming.Message{}` request into a domain request via
  the configured mapper and stores the original message in assigns.

  Halts with an error if the mapper returns an invalid response or is
  missing.
  """
  @impl Ming.Middleware
  def before_handle(context)

  def before_handle(%Context{assigns: %{mapper: mapper}, request: message} = context) do
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

  @doc """
  No-op after stage.
  """
  @impl Ming.Middleware
  def after_handle(context), do: context
end
