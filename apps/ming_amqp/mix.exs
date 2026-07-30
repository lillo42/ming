defmodule MingAmqp.MixProject do
  use Mix.Project

  @source_url "https://github.com/lillo42/ming"
  @version "0.2.0"

  def project do
    [
      app: :ming_amqp,
      version: @version,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "Ming AMQP",
      source_url: @source_url
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ming, in_umbrella: true},
      {:nimble_pool, "~> 1.1"},
      {:amqp, "~> 4.1"}
    ]
  end

  defp description do
    """
    AMQP (RabbitMQ) gateway for Ming.
    """
  end

  defp package do
    [
      maintainers: ["Rafael Andrade"],
      licenses: ["GPL-3.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(mix.exs lib)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
