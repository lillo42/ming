defmodule Ming.Handler do
  @moduledoc """
  Behaviour for request handlers.

  A handler is the terminal step of a `Ming.Pipeline`, invoked by
  `Ming.Middleware.HandlerRunner` with the request and the dispatch context.
  """

  alias Ming.Context

  @doc """
  Handles the request.

  The return value is normalized by `Ming.Middleware.HandlerRunner` into the
  context response: `:ok`, `nil`, `{:ok, value}`, `{:error, reason}`, a
  `%Ming.Context{}`, or any other value (wrapped in `{:ok, value}`).
  """
  @callback handle(request :: any(), context :: Context.t()) :: Ming.resp()
end
