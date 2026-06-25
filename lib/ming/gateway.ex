defmodule Ming.Gateway do
  @callback provision_infrastructure(args :: keyword()) :: :ok | {:error, any()}
end
