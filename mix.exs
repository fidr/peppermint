defmodule Peppermint.MixProject do
  use Mix.Project

  def project do
    [
      app: :peppermint,
      version: "0.2.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      package: package(),
      description: description(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:mint, "~> 1.0"},
      {:castore, "~> 0.1", optional: true},
      {:jason, "~> 1.2", only: :test},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def description do
    """
    Simple pool-less HTTP client build on Mint
    """
  end

  defp package do
    [
      name: :peppermint,
      files: ["lib", "mix.exs", "README*", "LICENSE*", "CHANGELOG*"],
      maintainers: ["Robin Fidder"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/fidr/peppermint"}
    ]
  end

  defp docs do
    [
      name: "Peppermint",
      source_url: "https://github.com/fidr/peppermint",
      homepage_url: "https://github.com/fidr/peppermint",
      main: "readme",
      extras: ["README.md"],
      groups_for_functions: [
        {:"Request", & &1[:section] == :base_request},
        {:"Request Helpers", & &1[:section] == :request_helper}
      ]
    ]
  end
end
