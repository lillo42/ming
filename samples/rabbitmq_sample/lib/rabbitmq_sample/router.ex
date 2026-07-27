defmodule RabbitMQSample.Router do
  @moduledoc """
  Routes messages consumed from RabbitMQ to their handlers.
  """

  use Ming.Router

  register(:order_shipped, handler: RabbitMQSample.OrderHandler)
end
