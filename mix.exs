defmodule OpenapiValidator.MixProject do
  use Mix.Project

  def project do
    [
      app: :openapi_validator,
      version: "0.0.1",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.1", override: true},
      {:plug, ">= 1.6.0"},
      {:ex_json_schema, "~> 0.6.1"},
      {:ex_spec, "~> 2.0.0", only: :test},
      {:freedom_formatter, "~> 1.1", only: [:dev, :test]},
    ]
  end
end
