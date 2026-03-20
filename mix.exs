defmodule Membrane.LiveFilter.MixProject do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/kim-company/membrane_live_filter_plugin"

  def project do
    [
      app: :membrane_live_filter_plugin,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      # Hex
      description: "Membrane filter that emits buffers at real-time pace, with tunable delay and absolute time support.",
      package: package(),
      # Docs
      name: "Membrane LiveFilter Plugin",
      source_url: @github_url,
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
      {:membrane_core, "~> 1.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["KIM Keep In Mind GmbH"],
      licenses: ["Apache-2.0"],
      organization: "kim-company",
      links: %{"GitHub" => @github_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      source_url: @github_url
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]
end
