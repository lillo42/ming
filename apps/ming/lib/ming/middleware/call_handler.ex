defmodule Ming.Middleware.CallHandler do
  @moduledoc """
  Terminal middleware responsible for invoking the configured handler.

  It normalizes handler return values into `Ming.Context.response`.
  """

  alias Ming.Context

  @behaviour Ming.Middleware

  @doc """
  Calls the configured handler and maps its result into context response.
  """
  def before_handle(
        %Context{
          handler: handler,
          request: request
        } = context
      ) do
    case handler.handle(request, context) do
      :ok ->
        Context.respond(context, :ok)

      nil ->
        Context.respond(context, {:ok, nil})

      {:error, reason} ->
        Context.respond(context, {:error, reason})

      {:ok, resp} ->
        Context.respond(context, {:ok, resp})

      %Context{} = resp ->
        resp

      resp when is_tuple(resp) and elem(resp, 0) == :error ->
        Context.respond(context, resp)

      resp when is_tuple(resp) and elem(resp, 0) == :ok ->
        Context.respond(context, resp)

      resp ->
        Context.respond(context, {:ok, resp})
    end
  end

  @doc """
  No-op after stage for handler invocation middleware.
  """
  def after_handle(context), do: context
end
