defmodule Ming.Middleware do
  @moduledoc """
  Behaviour for middleware participating in request dispatch.

  Middleware runs in two phases:
  - `before_handle/1` while entering the pipeline
  - `after_handle/1` while unwinding the pipeline
  """

  alias Ming.Context

  @doc """
  Runs before the handler execution stage.
  """
  @callback before_handle(context :: Context.t()) :: Context.t()

  @doc """
  Runs after the handler execution stage.
  """
  @callback after_handle(context :: Context.t()) :: Context.t()
end
