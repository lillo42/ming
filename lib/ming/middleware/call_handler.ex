defmodule Ming.Middleware.CallHandler do
  alias Ming.Context

  @behaviour Ming.Middleware

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
        Context.respond(context, :ok)

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

  def after_handle(context), do: context
end
