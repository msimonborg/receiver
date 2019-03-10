defmodule ExUnit.Mix.Tasks.Receiver.BuildTest do
  use ExUnit.Case
  import Mock
  alias Mix.Tasks.{Coveralls, Coveralls.SafeTravis, Coveralls.Travis}
  alias Mix.Tasks.{Credo, Docs, Format, Inch, Receiver.Build}

  test "runs build task" do
    with_mocks([
      {Coveralls.Html, [], [run: fn _ -> nil end]},
      {Credo, [], [run: fn _ -> nil end]},
      {Docs, [], [run: fn _ -> nil end]},
      {Format, [], [run: fn _ -> nil end]},
      {Inch, [], [run: fn _ -> nil end]}
    ]) do
      Build.do_run([])
      assert_called(Coveralls.Html.run([]))
      assert_called(Credo.run(["--strict"]))
      assert_called(Docs.run([]))
      assert_called(Format.run(["--check-equivalent"]))
      assert_called(Inch.run([]))
    end
  end

  test "runs coveralls.safe_travis" do
    with_mock Travis, run: fn _ -> nil end do
      SafeTravis.run(["hello"])
      assert_called(Travis.run(["hello"]))
    end
  end
end
