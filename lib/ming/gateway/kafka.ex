if Code.ensure_loaded?(:brod) do
  defmodule Ming.Gateway.Kafka do
    use Supervisor

    def start_link(args) do
      Supervisor.start_link(__MODULE__, args, name: Keyword.get(args, :name, __MODULE__))
    end

    @impl true
    def init(args) do
      name = Keyword.get(args, :name, __MODULE__)

      connection =
        args
        |> Keyword.fetch!(:connection)
        |> Keyword.put(:auto_start_producers, false)

      endpoints = Keyword.fetch!(connection, :endpoints)

      publications = Keyword.get(args, :publications, [])

      producers =
        Enum.map(publications, fn publication ->
          topic = Keyword.fetch!(args, :topic_or_queue)
        end)

      children = [
        %{
          id: name,
          type: :worker,
          restart: :permanent,
          start: [:brod, :start_link_client, [endpoints, name, connection]]
        }
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
    end

    @behaviour Ming.Gateway

    @impl Ming.Gateway
    def producer, do: Ming.Gateway.Kafka.Producer

    @impl Ming.Gateway
    def provision_infrastructure(_args) do
      :ok
    end
  end
end
