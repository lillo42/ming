defmodule KafkaSample.MixProject do
  use Mix.Project

  def project do
    [
      app: :kafka_sample,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {KafkaSample.Application, []}
    ]
  end

  defp deps do
    [
      {:ming, path: "../.."},
      {:brod, "~> 4.5"}
    ]
  end
end
