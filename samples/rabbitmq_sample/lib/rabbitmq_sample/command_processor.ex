defmodule RabbitMQSample.CommandProcessor do
  @moduledoc """
  Command processor for the RabbitMQ sample.

  Reads the gateway configuration from
  `config :rabbitmq_sample, RabbitMQSample.CommandProcessor` and starts the
  AMQP gateway on boot.
  """

  use Ming.CommandProcessor, otp_app: :rabbitmq_sample

  router(RabbitMQSample.Router)
end
