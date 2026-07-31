defmodule KafkaExSample.CommandProcessor do
  @moduledoc """
  Command processor for the kafka_ex sample.

  Reads the gateway configuration from
  `config :kafka_ex_sample, KafkaExSample.CommandProcessor` and starts the
  Kafka gateway on boot.
  """

  use Ming.CommandProcessor, otp_app: :kafka_ex_sample

  router(KafkaExSample.Router)
end
