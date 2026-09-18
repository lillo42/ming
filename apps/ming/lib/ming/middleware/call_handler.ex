defmodule Ming.Middleware.CallHandler do
  @moduledoc """
  Terminal middleware responsible for invoking the configured handler.

  It normalizes handler return values into `Ming.Context.response`.
  """

  require Logger

  alias Ming.Context

  @behaviour Ming.Middleware

  @impl Ming.Middleware
  def execute(
        %Context{request: request} = context,
        handler,
        next
      )
      when is_atom(handler) do
    context =
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

    next.(context)
  end

  def execute(%Context{metadata: %{handler: handler}} = context, next) do
    Logger.error("invalid handler: #{handler}")

    next.(context)
  end

  def execute(context, next), do: next.(context)
end
