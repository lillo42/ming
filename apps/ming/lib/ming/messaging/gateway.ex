defmodule Ming.Messaging.Gateway do
  @callback provisioner() :: :ok | {:error, any()}

  @callback producer(publication :: Keyword.t()) :: module() | {:error, any()}

  @callback consumer(subscription :: Keyword.t()) :: module() | {:error, any()}
end
