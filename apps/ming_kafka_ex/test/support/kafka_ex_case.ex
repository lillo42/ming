defmodule Ming.Gateway.KafkaEx.Case do
  @moduledoc """
  Test case for Kafka integration tests against a live broker.

  Assumes Kafka is running at `localhost:9092`.
  Start it with:

      docker compose -f docker-compose-kafka.yml up -d
  """

  use ExUnit.CaseTemplate

  @kafka_ex_endpoints [{"localhost", 9092}]

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  setup context do
    if :kafka_ex in Map.get(context, :tag, []) do
      {:ok, client} =
        KafkaEx.API.start_client(
          brokers: @kafka_ex_endpoints,
          consumer_group: :no_consumer_group
        )

      try do
        case KafkaEx.API.metadata(client) do
          {:ok, _metadata} ->
            :ok

          {:error, reason} ->
            raise_broker_down(reason)
        end
      catch
        :exit, reason -> raise_broker_down(reason)
      after
        GenServer.stop(client)
      end
    end

    [kafka_ex_endpoints: @kafka_ex_endpoints]
  end

  defp raise_broker_down(reason) do
    raise """
    Kafka is not running at #{inspect(@kafka_ex_endpoints)} (#{inspect(reason)}).
    Start it with: docker compose -f docker-compose-kafka.yml up -d
    """
  end

  @doc """
  Returns a unique name for a topic, gateway or consumer group.
  """
  def unique_name(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end

  @doc """
  Returns the default Kafka endpoints used by tests.
  """
  def kafka_ex_endpoints, do: @kafka_ex_endpoints

  @doc """
  Deletes topics using a short-lived client.

  Safe to call from `on_exit` callbacks, where supervised clients are
  already stopped (the test supervisor shuts down before `on_exit` runs).
  """
  def delete_topics(topics) do
    {:ok, client} =
      KafkaEx.API.start_client(
        brokers: @kafka_ex_endpoints,
        consumer_group: :no_consumer_group
      )

    try do
      KafkaEx.API.delete_topics(client, topics, 10_000)
    after
      GenServer.stop(client)
    end
  end
end
