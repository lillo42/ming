defmodule KafkaExSample.Router do
  @moduledoc """
  Routes messages consumed from Kafka to their handlers.
  """

  use Ming.Router

  register(:order_created, handler: KafkaExSample.OrderHandler)
  register(:orders_dead_letter, handler: KafkaExSample.DeadLetterHandler)
end
