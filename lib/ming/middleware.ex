defmodule Ming.Middleware do
  @callback before_dispatch(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()

  @callback before_after(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()

  @callback after_failure(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()
end
