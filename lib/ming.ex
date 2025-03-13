defmodule Ming do
  @moduledoc """

  """
  alias Ming.Pipeline.Dispatcher

  @spec post(struct(), map(), list(Ming.Pipeline.Middleware)) :: :ok | {:error, any()}
  def post(request, metadata \\ %{}, middlewares \\ []) do
    middlewares = [Ming.Pipeline.MapMessage | middlewares]
    middlewares = [middlewares | Ming.Pipeline.Sender]

    Dispatcher.dispatch(request, metadata, middlewares)
  end
end
