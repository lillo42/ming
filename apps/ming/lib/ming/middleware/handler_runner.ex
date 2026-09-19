defmodule Ming.Middleware.HandlerRunner do
  @moduledoc """
  Terminal middleware responsible for running the configured handler.

  It normalizes handler return values into `Ming.Context.response`:

    * `:ok` stays `:ok`
    * `nil` becomes `{:ok, nil}`
    * `{:ok, value}` / `{:error, reason}` pass through
    * a `%Ming.Context{}` is used as the new context
    * any other value becomes `{:ok, value}`

  Being terminal, it never calls `next` — middleware with a higher `:order`
  would never run.
  """

  alias Ming.Context

  @behaviour Ming.Middleware

  @impl Ming.Middleware
  def execute(%Context{request: request} = context, handler, _next)
      when is_atom(handler) and not is_nil(handler) do
    case handler.handle(request, context) do
      %Context{} = context -> context
      :ok -> Context.respond(context, :ok)
      nil -> Context.respond(context, {:ok, nil})
      {:ok, resp} -> Context.respond(context, {:ok, resp})
      {:error, reason} -> Context.respond(context, {:error, reason})
      resp -> Context.respond(context, {:ok, resp})
    end
  end

  def execute(%Context{routing_key: routing_key}, handler, _next) do
    raise ArgumentError,
          "invalid handler #{inspect(handler)} for routing key #{inspect(routing_key)}"
  end
end
