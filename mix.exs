defmodule Receiver.MixProject do
  use Mix.Project

  @version "0.2.2"

  def project do
    [
      app: :receiver,
      version: @version,
      elixir: ">= 1.8.0",
      start_permanent: false,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.travis": :test,
        "coveralls.safe_travis": :test,
        "receiver.build": :test
      ],
      description: description(),
      package: package(),
      source_url: "https://github.com/msimonborg/receiver",
      homepage_url: "https://github.com/msimonborg/receiver",
      name: "Receiver"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Receiver.Application, []}
    ]
  end

  defp description do
    "Conveniences for creating simple processes that hold state."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/msimonborg/receiver"}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: [:dev, :test]},
      {:excoveralls, ">= 0.0.0", only: :test},
      {:stream_data, ">= 0.0.0", only: :test},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:inch_ex, ">= 0.0.0", only: [:dev, :test]},
      {:mock, ">= 0.0.0", only: :test},
      {:jason, ">= 0.0.0", only: [:dev, :test]}
    ]
  end
end
