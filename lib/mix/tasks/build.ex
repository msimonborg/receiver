if Mix.env() == :test do
  defmodule Mix.Tasks.Receiver.Build do
    @moduledoc false
    import IO.ANSI, only: [cyan: 0, bright: 0]
    alias Mix.Tasks.{Coveralls, Credo, Docs, Format, Inch}

    use Mix.Task

    @preferred_cli_env :test
    @required_elixir_version "1.8"

    @spec run(argv :: [String.t()]) :: nil
    def run(argv) do
      {opts, argv, _} = OptionParser.parse(argv, switches: [format: :boolean])
      if Keyword.get(opts, :format, true), do: run_formatter(argv)
      do_run(argv)
    end

    @spec run_formatter([binary()]) :: any()
    def run_formatter(argv) do
      if System.version() >= @required_elixir_version do
        IO.puts("#{cyan()}#{bright()}Running formatter")
        Format.run(["--check-equivalent" | argv])
      else
        raise RuntimeError, """
        #{bright()}Elixir version must be >= #{@required_elixir_version}. Detected version:

          * #{System.version()}

        Please upgrade to Elixir #{@required_elixir_version} or above to continue development on this project.
        """
      end
    end

    @spec do_run([binary()]) :: nil
    def do_run(argv) do
      Coveralls.Html.run(argv)
      Inch.run(argv)
      Docs.run(argv)
      Credo.run(["--strict" | argv])
    end
  end
end
