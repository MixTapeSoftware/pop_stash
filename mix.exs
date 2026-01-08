defmodule PopStash.MixProject do
  use Mix.Project

  def project do
    [
      app: :pop_stash,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  def application do
    [
      mod: {PopStash.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp releases do
    [
      pop_stash: [
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  defp deps do
    [
      # Runtime
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16"},
      {:telemetry, "~> 1.2"},
      {:phoenix_pubsub, "~> 2.1"},

      # Database
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:pgvector, "~> 0.3"},

      # Embeddings
      {:bumblebee, "~> 0.6"},
      {:nx, "~> 0.9"},
      {:exla, "~> 0.9"},

      # Typesense
      {:typesense_ex, git: "https://github.com/MixTapeSoftware/typesense_ex"},

      # Dev/test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:mimic, "~> 1.10", only: :test},
      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false},
      {:tidewave, "~> 0.1", only: :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      lint: [
        "format --check-formatted",
        "credo --strict",
        "sobelow --config"
      ]
    ]
  end
end
