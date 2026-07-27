defmodule Ming.Message.Middleware.DecodeMessageToRequest do
  @moduledoc """
  Middleware that converts a `%Ming.Message{}` back to a domain request
  using a configured mapper module.

  Expects `:mapper` in context assigns; falls back to
  `metadata[:default_message_mapper]` and finally to
  `Ming.Message.Mapper.Json` when no mapper is assigned.
  """

  alias Ming.Context

  @behaviour Ming.Middleware

  @doc """
  Decodes the current `%Ming.Message{}` request into a domain request via
  the configured mapper and stores the original message in assigns.

  Halts with an error if the mapper returns an invalid response.
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
    mapper =
      context.assigns[:mapper] ||
        get_in(context.metadata || %{}, [:default_message_mapper]) ||
        Ming.Message.Mapper.Json

    before_handle(%Context{context | assigns: Map.put(context.assigns, :mapper, mapper)})
  end

  @doc """
  No-op after stage.
  """
  @impl Ming.Middleware
  def after_handle(context), do: context
end
