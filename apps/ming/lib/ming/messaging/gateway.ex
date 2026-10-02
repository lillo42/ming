defmodule Ming.Messaging.Gateway do
  @callback producer(publication :: map()) :: module() | {:error, any()}

  @callback consumer(subscription :: map()) :: module() | {:error, any()}
end
