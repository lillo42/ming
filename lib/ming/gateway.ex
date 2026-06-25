defmodule Ming.Gateway do
  @moduledoc """
  Behaviour for messaging gateway adapters.

  Implementations are responsible for provisioning infrastructure
  (exchanges, queues, topics) before the gateway is started.
  """

  @doc """
  Provisions messaging infrastructure (exchanges, queues, bindings, topics, etc.)
  before the gateway supervision tree starts.

  Called synchronously by `Ming.Gateway.Supervisor` during init.
  """
  @callback provision_infrastructure(args :: keyword()) :: :ok | {:error, any()}
end
