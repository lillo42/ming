defmodule Ming.Handler do
  @moduledoc """
  Behaviour implemented by request handlers.

  Handlers receive the incoming request and the current `Ming.Context`.
  """

  alias Ming.Context

  @doc """
  Handles a request and returns a pipeline-compatible response.
  """
  @callback handle(request :: any(), context :: Context.t()) :: Ming.resp()
end
