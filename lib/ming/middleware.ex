defmodule Ming.Middleware do
  alias Ming.Context

  @callback before_handle(context :: Context.t()) :: Context.t()

  @callback after_handle(context :: Context.t()) :: Context.t()
end
