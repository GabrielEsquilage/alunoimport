defmodule Alunoimport.MixProject do
  use Mix.Project

  def project do
    [
      app: :alunoimport,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Alunoimport.Application, []},
      extra_applications: [:logger, :ecto, :postgrex]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Cliente HTTP robusto
      {:httpoison, "~> 2.2"},
      # Parser JSON extremamente rápido
      {:jason, "~> 1.4"},
      # Parser CSV de alta performance (o melhor para Elixir)
      {:nimble_csv, "~> 1.2"},
      # Ecto para banco de dados
      {:ecto_sql, "~> 3.10"},
      # Driver do postgrex
      {:postgrex, "~> 0.17.5"}
    ]
  end
end
