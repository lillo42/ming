defmodule Ming do
  @moduledoc """
  Core namespace for Ming.

  This module currently exposes shared project types used by the routing,
  dispatching, and handler contracts.
  """

  @typedoc """
  Common response shape expected by handlers and dispatch pipeline.
  """
  @type resp :: :ok | {:ok, any()} | {:error, any()}
end
