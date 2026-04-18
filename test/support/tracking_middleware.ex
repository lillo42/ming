defmodule Ming.TrackingMiddleware do
  @moduledoc false

  @behaviour Ming.Middleware

  def init(opts), do: opts

  def before_dispatch(pipeline, _opts) do
    Ming.Pipeline.assign(pipeline, :before_dispatch_called, true)
  end

  def after_dispatch(pipeline, _opts) do
    Ming.Pipeline.assign(pipeline, :after_dispatch_called, true)
  end

  def after_failure(pipeline, _opts) do
    Ming.Pipeline.assign(pipeline, :after_failure_called, true)
  end
end
