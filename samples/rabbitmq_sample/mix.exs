defmodule RabbitMQSample.MixProject do
  use Mix.Project

  def project do
    [
      app: :rabbitmq_sample,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {RabbitMQSample.Application, []}
    ]
  end

  defp deps do
    [
      {:ming, path: "../../apps/ming"},
      {:ming_amqp, path: "../../apps/ming_amqp"}
    ]
  end
end
