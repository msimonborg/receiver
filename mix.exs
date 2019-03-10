defmodule Receiver.MixProject do
  use Mix.Project

  def project do
    [
      app: :receiver,
      version: "0.1.7",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.travis": :test,
        "coveralls.safe_travis": :test
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
      {:ex_doc, "~> 0.19.3", only: [:dev, :test]},
      {:excoveralls, "~> 0.10", only: :test},
      {:stream_data, "~> 0.1", only: :test},
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 0.5", only: [:dev], runtime: false},
      {:inch_ex, "~> 2.0", only: [:docs]}
    ]
  end
end
