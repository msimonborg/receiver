defmodule Mix.Tasks.Receiver.Build do
  @moduledoc false
  alias Mix.Tasks.Coveralls
  alias Mix.Tasks.Credo
  alias Mix.Tasks.Docs

  use Mix.Task

  @preferred_cli_env :test

  def run([]) do
    Coveralls.Html.run([])
    Credo.run(["--strict"])
    Docs.run([])
  end
end
