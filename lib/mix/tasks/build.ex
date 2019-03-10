if Mix.env() == :test do
  defmodule Mix.Tasks.Receiver.Build do
    @moduledoc false
    import IO.ANSI, only: [cyan: 0, bright: 0]
    alias Mix.Tasks.{Coveralls, Credo, Docs, Format, Inch}

    use Mix.Task

    @preferred_cli_env :test

    @spec run([]) :: [any()]
    def run([]) do
      IO.puts("#{cyan()}#{bright()}Running formatter")
      do_run([])
    end

    @spec do_run([binary()]) :: [any()]
    def do_run(argv) do
      Format.run(["--check-equivalent"])
      Coveralls.Html.run(argv)
      Credo.run(["--strict"])
      Inch.run(argv)
      Docs.run(argv)
    end
  end
end
