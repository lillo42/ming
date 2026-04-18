defmodule Ming.RaiseBeforeDispatchMiddleware do
  @moduledoc false

  @behaviour Ming.Middleware

  @impl true
  def init(opts), do: opts

  @impl true
  def before_dispatch(_pipeline, _opts) do
    raise ArgumentError, "middleware raised"
  end

  @impl true
  def after_dispatch(pipeline, _opts), do: pipeline

  @impl true
  def after_failure(pipeline, _opts), do: pipeline
end
