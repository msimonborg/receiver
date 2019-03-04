defmodule Receiver.MixProject do
  use Mix.Project

  def project do
    [
      app: :receiver,
      version: "0.1.3",
      elixir: "~> 1.8",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
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
      {:ex_doc, "~> 0.19.3", only: :dev}
    ]
  end
end
