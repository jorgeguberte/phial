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
      extra_applications: [:logger],
      mod: {Phial.Application, []}
    ]
  end

  defp deps do
    [
      {:jido, "~> 2.3"},
      {:jido_ai, "~> 2.3"}
    ]
  end
end
