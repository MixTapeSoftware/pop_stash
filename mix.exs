defmodule PopStash.MixProject do
  use Mix.Project

  def project do
    [
      app: :pop_stash,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {PopStash.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Runtime
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:telemetry, "~> 1.2"},

      # Dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.10", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.1", only: :dev}
    ]
  end
end
