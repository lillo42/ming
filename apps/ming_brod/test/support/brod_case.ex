defmodule Ming.Gateway.Brod.Case do
  @moduledoc """
  Test case for Kafka integration tests against a live broker.

  Assumes Kafka is running at `localhost:9092`.
  Start it with:

      docker compose -f docker-compose-kafka.yml up -d
  """

  use ExUnit.CaseTemplate

  @brod_endpoints [{"localhost", 9092}]

  using do
    quote do
      import unquote(__MODULE__)
    end
  end

  setup context do
    if :brod in Map.get(context, :tag, []) do
      try do
        {:ok, _metadata} = :brod.get_metadata(@brod_endpoints)
      catch
        _, reason ->
          raise """
          Kafka is not running at #{inspect(@brod_endpoints)} (#{inspect(reason)}).
          Start it with: docker compose -f docker-compose-kafka.yml up -d
          """
      end
    end

    [brod_endpoints: @brod_endpoints]
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
  def brod_endpoints, do: @brod_endpoints
end
