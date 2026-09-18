defmodule Ming.Middleware do
  @moduledoc """
  TODO: Update
  """

  alias Ming.Context

  @doc """
  Runs before the handler execution stage.
  """
  @callback execute(
              context :: Context.t(),
              args :: any(),
              next :: (Context.t() -> Context.t())
            ) ::
              Context.t()
end
