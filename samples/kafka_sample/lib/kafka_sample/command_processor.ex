defmodule KafkaSample.CommandProcessor do
  @moduledoc """
  Command processor for the Kafka sample.

  Reads the gateway configuration from
  `config :kafka_sample, KafkaSample.CommandProcessor` and starts the Kafka
  gateway on boot.
  """

  use Ming.CommandProcessor, otp_app: :kafka_sample

  router(KafkaSample.Router)
end
