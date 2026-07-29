defmodule Ming.Umbrella.MixProject do
  use Mix.Project

  @source_url "https://github.com/lillo42/ming"
  @version "0.2.0"

  def project do
    [
      apps_path: "apps",
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :test,

      # Docs
      name: "Ming",
      source_url: @source_url,
      docs: docs()
    ]
  end

  defp deps do
    [
      # Docs
      {:ex_doc, "~> 0.20", only: :dev, runtime: false},

      # Analyser
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "Ming",
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"],
      extras: [
        "README.md",
        "guides/getting_started.md",
        "guides/command_processor.md",
        "guides/gateways.md",
        "guides/middleware.md",
        "CHANGELOG.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/getting_started.md",
          "guides/command_processor.md",
          "guides/gateways.md",
          "guides/middleware.md"
        ]
      ]
    ]
  end
end
