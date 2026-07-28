defmodule Ming.Message.Middleware.DecodeMessageToRequest do
  @moduledoc """
  Middleware that converts a `%Ming.Message{}` back to a domain request
  using a configured mapper module.

  Expects `:mapper` in context assigns; falls back to
  `metadata[:default_message_mapper]` and finally to
  `Ming.Message.Mapper.Json` when no mapper is assigned.
  """

  require Logger

  alias Ming.Context

  @behaviour Ming.Middleware

  @doc """
  Decodes the current `%Ming.Message{}` request into a domain request via
  the configured mapper and stores the original message in assigns.

  Decodes the current `%Ming.Message{}` request into a domain request via
  the configured mapper and stores the original message in assigns.

  Halts with `{:reject, :unaccepted}` when the mapper fails to decode the
  message (an error reply or a raised exception), marking it as an
  unacceptable message.
  """
  @impl Ming.Middleware
  def before_handle(context)

  def before_handle(%Context{assigns: %{mapper: mapper}, request: message} = context) do
    try do
      case mapper.to_request(message, context) do
        {:ok, request} ->
          %Context{context | request: request}
          |> Context.assign(:original_message, message)

        %Context{} = other_context ->
          other_context

        {:error, reason} ->
          unaccepted(context, reason)

        request ->
          %Context{context | request: request}
          |> Context.assign(:original_message, message)
      end
    rescue
      e ->
        unaccepted(context, e)
    end
  end

  defp unaccepted(context, reason) do
    Logger.error("unacceptable message, failed to decode payload: #{inspect(reason)}")

    context
    |> Context.halt()
    |> Context.respond({:reject, :unaccepted})
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
