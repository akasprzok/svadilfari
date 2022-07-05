defmodule Svadilfari.MixProject do
  use Mix.Project

  @version "0.1.0"
  @url "https://github.com/akasprzok/svadilfari"

  def project do
    [
      app: :svadilfari,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Hex
      description: description(),
      package: package(),
      source_url: @url,
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_clie_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
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
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:sleipnir, "~> 0.1"}
    ]
  end

  defp description do
    """
    A Logger Backend for sending logs directly to Grafana Loki.
    """
  end

  defp package do
    [
      licneses: ["MIT"],
      links: %{"GitHub" => @url},
      files: ~w(mix.exs lib README.md LICENSE.md),
      maintainers: ["Andreas Kasprzok"]
    ]
  end

  defp docs do
    [
      main: "Svadilfari",
      extras: ["README.md"]
    ]
  end
end
