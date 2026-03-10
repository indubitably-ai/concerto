defmodule Concerto.MixProject do
  use Mix.Project

  def project do
    [
      app: :concerto,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {Concerto.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:postgrex, "~> 0.19"},
      {:yaml_elixir, "~> 2.11"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
