defmodule GeneratedFunctionsTest.Runner do
  defmacro run_tests do
    quote do
      test "it can get the state of the receiver" do
        assert get_tester() == 0
      end

      test "it can update the state of the receiver" do
        update_tester(&(&1 + 1))
        assert get_tester() == 1
      end

      test "it can get and update the state of the receiver" do
        assert get_and_update_tester(&{&1, &1 + 1}) == 0
        assert get_tester() == 1
      end

      test "it can stop the receiver", %{pid: pid} do
        assert Process.alive?(pid) == true
        assert :ok = stop_tester()
        assert Process.alive?(pid) == false
      end
    end
  end
end

defmodule GeneratedFunctionsTest do
  use ExUnit.Case
  use ExUnitReceiver, as: :tester
  import GeneratedFunctionsTest.Runner

  describe "initialized with a function" do
    setup do
      {:ok, pid} = start_tester(fn -> 0 end)
      %{pid: pid}
    end

    run_tests()
  end

  describe "initialized with a module, function, and arguments" do
    setup do
      {:ok, pid} = start_tester(Kernel, :-, [1, 1])
      %{pid: pid}
    end

    run_tests()
  end
end
