if Mix.env() == :test do
  defmodule Mix.Tasks.Receiver.Build do
    @moduledoc false
    alias Mix.Tasks.{Coveralls, Credo, Docs, Inch}

    use Mix.Task

    @preferred_cli_env :test

    def run([]) do
      Coveralls.Html.run([])
      Credo.run(["--strict"])
      Inch.run([])
      Docs.run([])
    end
  end
end
