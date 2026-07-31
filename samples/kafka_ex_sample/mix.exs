defmodule KafkaExSample.MixProject do
  use Mix.Project

  def project do
    [
      app: :kafka_ex_sample,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {KafkaExSample.Application, []}
    ]
  end

  defp deps do
    [
      {:ming, path: "../../apps/ming"},
      {:ming_kafka_ex, path: "../../apps/ming_kafka_ex"}
    ]
  end
end
