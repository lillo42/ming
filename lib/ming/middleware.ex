defmodule Ming.Middleware do
  @moduledoc """
  The middleware behaviour
  """

  @doc """
  The action executes before dispatch
  """
  @callback before_dispatch(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()

  @doc """
  The action executes after dispatch
  """
  @callback before_after(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()

  @doc """
  The action executes after failure 
  """
  @callback after_failure(pipeline :: Ming.Pipeline.t()) :: Ming.Pipeline.t()
end
