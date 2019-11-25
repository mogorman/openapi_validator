defmodule OpenapiValidator.MixProject do
  use Mix.Project

  def project do
    [
      app: :openapi_validator,
      version: "0.0.3",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/mogorman84/openapi_validator",
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
    ]
  end

  defp description() do
    "Tools for your phoenix project for validating openapi spec in your application."
  end

  defp package() do
    [
      maintainers: ["Matthew O'Gorman"],
      links: %{"GitHub" => "https://github.com/mogorman84/openapi_validator"},
      licenses: ["MIT"],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.1"},
      {:plug, ">= 1.6.0"},
      {:ex_json_schema, "~> 0.7"},
      {:ex_spec, "~> 2.0.0", only: :test},
      {:freedom_formatter, "~> 1.1", only: [:dev, :test]},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
    ]
  end
end
