defmodule ExUnit.Mix.Tasks.Receiver.BuildTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  import Mock
  alias Mix.Tasks.{Coveralls, Coveralls.SafeTravis, Coveralls.Travis}
  alias Mix.Tasks.{Credo, Docs, Format, Inch, Receiver.Build}

  describe "mix receiver.build" do
    test "runs build task" do
      with_mocks([
        {Coveralls.Html, [], [run: fn _ -> nil end]},
        {Credo, [], [run: fn _ -> nil end]},
        {Docs, [], [run: fn _ -> nil end]},
        {Inch, [], [run: fn _ -> nil end]}
      ]) do
        Build.run(["--no-format"])
        assert_called(Coveralls.Html.run([]))
        assert_called(Credo.run(["--strict"]))
        assert_called(Docs.run([]))
        assert_called(Inch.run([]))
      end
    end

    test "runs the formatter when Elixir >= 1.8" do
      if System.version() >= "1.8" do
        with_mock(Format, run: fn _ -> nil end) do
          assert capture_io(fn -> Build.run_formatter([]) end)
                 |> String.contains?("Running formatter")

          assert_called(Format.run(["--check-equivalent"]))
        end
      else
        assert_raise RuntimeError, ~r/Elixir version must be >= 1.8/, fn ->
          Build.run_formatter([])
        end
      end
    end
  end

  describe "mix coveralls.safe_travis" do
    test "runs" do
      with_mock Travis, run: fn _ -> nil end do
        SafeTravis.run(["hello"])
        assert_called(Travis.run(["hello"]))
      end
    end

    test "catches ExCoveralls.ReportUploadError" do
      with_mock Travis, run: fn _ -> raise ExCoveralls.ReportUploadError end do
        assert capture_io(:stderr, fn -> SafeTravis.run(["hello"]) end)
      end
    end
  end
end
