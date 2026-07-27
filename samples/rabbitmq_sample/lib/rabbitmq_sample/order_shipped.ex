defmodule RabbitMQSample.OrderShipped do
  @moduledoc """
  Event published to the "events" exchange in RabbitMQ.
  """

  @derive JSON.Encoder
  defstruct [:id, :tracking_code]
end
