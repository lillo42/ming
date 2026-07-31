defmodule KafkaExSample.OrderCreated do
  @moduledoc """
  Event published to the "orders" Kafka topic.
  """

  @derive JSON.Encoder
  defstruct [:id, :amount]
end
