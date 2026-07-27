defmodule KafkaSample.Router do
  @moduledoc """
  Routes messages consumed from Kafka to their handlers.
  """

  use Ming.Router

  register(:order_created, handler: KafkaSample.OrderHandler)
end
