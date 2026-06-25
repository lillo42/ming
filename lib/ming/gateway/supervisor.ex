defmodule Ming.Gateway.Supervisor do
  @moduledoc """
  Supervisor that starts all configured messaging gateways.

  Before starting each gateway, its adapter's `provision_infrastructure/1`
  callback is invoked to create exchanges, queues, and bindings.

  ## Example

      children = [
        {Ming.Gateway.Supervisor, [
          [
            adapter: Ming.Gateway.AMQP,
            name: :my_gateway,
            config: [...]
          ]
        ]}
      ]
  """

  use Supervisor

  @doc """
  Starts the gateway supervisor linked to the current process.
  """
  @spec start_link([keyword()]) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    Supervisor.init(create_children(init_arg), strategy: :one_for_one)
  end

  defp create_children([]), do: []

  defp create_children([current | next]) do
    acc = create_children(next)

    adapter = Keyword.fetch!(current, :adapter)

    case adapter.provision_infrastructure(current) do
      :ok ->
        [{adapter, current} | acc]

      {:error, reason} ->
        raise "Failed to provision infrastructure for #{inspect(adapter)}: #{inspect(reason)}"
    end
  end
end
