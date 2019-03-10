defmodule ExUnit.Mix.Tasks.Receiver.BuildTest do
  use ExUnit.Case
  import Mock
  import ExUnit.CaptureIO
  alias Mix.Tasks.{Coveralls, Coveralls.SafeTravis, Coveralls.Travis, Credo, Docs, Receiver.Build}

  test "runs build task" do
    with_mocks([
      {Coveralls.Html, [], [run: fn _ -> nil end]},
      {Credo, [], [run: fn _ -> nil end]},
      {Docs, [], [run: fn _ -> nil end]}
    ]) do

      Build.run([])
      assert_called Coveralls.Html.run([])
      assert_called Credo.run(["--strict"])
      assert_called Docs.run([])
    end
  end

  test "runs coveralls.safe_travis" do
    # with_mock Travis, [run: fn _ -> raise ExCoveralls.ReportUploadError end] do
      # assert capture_io(fn -> SafeTravis.run(["hello"]) end) == "Failed coveralls upload: error"
    with_mock Travis, [run: fn _ -> nil end] do
      SafeTravis.run(["hello"])
      assert_called Travis.run(["hello"])
    end
  end
end
