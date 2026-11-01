defmodule Ming.Messaging.InMemory.ProducerTest do
  use ExUnit.Case, async: false

  alias Ming.Context
  alias Ming.Messaging.InMemory.Producer
  alias Ming.Messaging.InMemory.Queue
  alias Ming.Messaging.Message

  defp context(publication) do
    %Context{
      id: "id",
      correlation_id: "corr",
      request: %{},
      routing_key: :test,
      timeout: :infinity,
      timestamp: DateTime.utc_now(),
      metadata: %{ming_publication: publication}
    }
  end

  defp message do
    %Message{id: "id", payload: "payload", routing_key: :test, timestamp: DateTime.utc_now()}
  end

  test "produce pushes the message onto the queue resolved from the routing key" do
    start_supervised!({Queue, name: :producer_test_rk})

    message = message()
    assert :ok = Producer.produce(message, context(%{routing_key: :producer_test_rk}))
    assert Queue.take(:producer_test_rk, 10) == [message]
  end

  test "produce resolves the queue from the :queue option" do
    start_supervised!({Queue, name: :producer_test_explicit})

    publication = %{routing_key: :producer_test_rk_unused, queue: :producer_test_explicit}

    message = message()
    assert :ok = Producer.produce(message, context(publication))
    assert Queue.take(:producer_test_explicit, 10) == [message]
  end

  test "produce on a missing queue returns an error" do
    assert Producer.produce(message(), context(%{routing_key: :producer_test_missing})) ==
             {:error, {:queue_not_found, :producer_test_missing}}
  end
end
