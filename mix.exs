defmodule Ming.MixProject do
  use Mix.Project

  @source_url "https://github.com/lillo42/ming"
  @version "0.1.0"

  def project do
    [
      app: :ming,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,

      # Hex
      description: "A toolkit for building messagin apps for Elixir",
      package: package(),

      # Docs
      name: "Ming",
      description: description(),
      docs: docs()
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
      # Telemetry
      {:telemetry, "~> 0.4 or ~> 1.0"},
      {:telemetry_registry, "~> 0.2 or ~> 0.3"},

      # Docs
      {:ex_doc, "~> 0.20", only: :dev, runtime: false},

      # Analyser
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    Use Ming to build your own Elixir applications following the CQRS pattern.
    """
  end

  defp docs do
    [
      main: "Ming",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp package do
    [
      maintainers: ["Rafael Andrade"],
      licenses: ["GPL-3.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(.formatter.exs mix.exs README.md CHANGELOG.md lib)
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
