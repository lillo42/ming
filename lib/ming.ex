defmodule Ming do
  @moduledoc """

  """
  alias Ming.Pipeline.Dispatcher

  @spec send(struct(), map()) :: :ok | {:error, any()}
  def send(_request, _metadata) do
  end

  @spec publish(struct(), map()) :: :ok | {:error, any()}
  def publish(_request, _metadata) do
  end

  @spec post(struct(), map(), list(Ming.Pipeline.Middleware)) :: :ok | {:error, any()}
  def post(request, metadata \\ %{}, middlewares \\ []) do
    middlewares = [Ming.Pipeline.MapToMessage | middlewares] ++ [Ming.Pipeline.Sender]

    Dispatcher.dispatch(request, metadata, middlewares)
  end
end
