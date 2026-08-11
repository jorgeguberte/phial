defmodule Phial.MixProject do
  use Mix.Project

  def project do
    [
      app: :phial,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Phial.Application, []}
    ]
  end

  defp deps do
    [
      {:jido, "~> 2.3"},
      {:jido_ai, "~> 2.3"},
      {:firecrawl, "~> 1.8"},
      {:phoenix, "~> 1.8.10"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_view, "~> 1.2.7"},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.12"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
