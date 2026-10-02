defmodule Ming.Messaging.InMemory.Gateway do
  use Supervisor

  @behaviour Ming.Messaging.Gateway

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: config.name)
  end

  @impl Ming.Messaging.Gateway
  def producer(_publication), do: Ming.Messaging.InMemory.Producer

  @impl Ming.Messaging.Gateway
  def consumer(_subscription), do: Ming.Messaging.InMemory.Consumer

  @impl true
  def init(config) do
    provisioners = get_provisioner(config)

    queues =
      create(provisioners, [])
      |> Enum.uniq_by(&Keyword.fetch!(elem(&1, 1), :name))

    case validate(queues, provisioners) do
      :ok ->
        Supervisor.init(queues, strategy: :one_for_one)

      error ->
        error
    end
  end

  defp get_provisioner(config) do
    publications =
      config
      |> Map.get(:publication, [])
      |> Enum.map(fn item ->
        provisioner = Map.get(item, :provisioner, :assume)
        {provisioner, item.queue}
      end)

    subscription =
      config
      |> Map.get(:subscription, [])
      |> Enum.map(fn item ->
        provisioner = Map.get(item, :provisioner, :assume)
        {provisioner, item.queue}
      end)

    publications ++ subscription
  end

  defp create([], acc), do: acc

  defp create([{:create, queue} | provisioners], acc) do
    create(
      provisioners,
      [{Ming.Messaging.InMemory.Queue, name: queue} | acc]
    )
  end

  defp create([{_provisioner, _queue} | provisioners], acc), do: create(provisioners, acc)

  defp validate(_queues, []), do: :ok

  defp validate(queues, [{:validate, queue} | provisioners]) do
    case Enum.any?(queues, &(Keyword.fetch!(elem(&1, 1), :name) == queue)) do
      true ->
        validate(queues, provisioners)

      false ->
        {:error, {:queue_not_found, queue}}
    end
  end

  defp validate(queues, [_provisioner | provisioners]), do: validate(queues, provisioners)
end
