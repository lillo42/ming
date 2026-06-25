defmodule Ming.Gateway.Supervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    # it'll be an array of gatways
    # [
    #   [adapter: module(), name: [], publisher: [], subscription: []]
    # ]
    #

    Supervisor.init(create_children(init_arg), strategy: :one_for_one)
  end

  defp create_children([]), do: []

  defp create_children([current | next]) do
    acc = create_children(next)

    adapter = Keyword.fetch!(current, :adapter)
    :ok = adapter.provision_infrastructure(current)

    [{adapter, current} | acc]
  end
end
