defmodule ExUnit.GeneratedFunctionsTest.Runner do
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
        assert get_and_update_tester(& {&1, &1 + 1}) == 0
        assert get_tester() == 1
      end

      test "it can stop the receiver" do
        assert :ok = stop_tester()
        catch_exit get_tester()
      end
    end
  end
end

defmodule ExUnit.GeneratedFunctionsTest do
  use ExUnit.Case
  use Receiver, test: true, as: :tester
  import ExUnit.GeneratedFunctionsTest.Runner

  describe "initialized with a function" do
    setup do
      start_tester(fn -> 0 end)
      :ok
    end

    run_tests()
  end

  describe "initialized with a module, function, and arguments" do
    setup do
      start_tester(Kernel, :-, [1, 1])
      :ok
    end

    run_tests()
  end
end
