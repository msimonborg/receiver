defmodule LookupTest do
  use ExUnit.Case
  use ExUnitProperties
  use Receiver, name: Test

  setup_all do
    {:ok, pid} = start_receiver()
    %{pid: pid}
  end

  describe "which_name/1" do
    test "looks up the registered name of a receiver by atom, pid or two-element tuple", %{
      pid: pid
    } do
      assert Receiver.which_name(pid) == Test
      assert Receiver.which_name({__MODULE__, :receiver}) == Test
      assert Receiver.which_name(Test) == Test
    end

    property "returns nil if no receiver is found" do
      check all(
              name <- atom(:alias),
              tuple <- tuple({atom(:alias), atom(:alphanumeric)}),
              pid = spawn(fn -> nil end),
              name != Test,
              tuple != {__MODULE__, :receiver}
            ) do
        assert Receiver.which_name(name) == nil
        assert Receiver.which_name(tuple) == nil
        assert Receiver.which_name(pid) == nil
      end
    end
  end

  describe "whereis/1" do
    test "returns a pid when passed a registered receiver tuple", %{pid: pid} do
      assert Receiver.whereis({__MODULE__, :receiver}) == pid
    end

    property "returns nil when passed an unregistered receiver tuple" do
      check all(
              tuple <- tuple({atom(:alias), atom(:alphanumeric)}),
              tuple != {__MODULE__, :receiver}
            ) do
        assert Receiver.whereis(tuple) == nil
      end
    end

    test "returns a pid when passed a registered receiver name", %{pid: pid} do
      assert Receiver.whereis(Test) == pid
    end

    property "returns nil when passed an unregistered name" do
      check all(
              name <- atom(:alias),
              name != Test,
              {:ok, _} = Agent.start_link(fn -> nil end, name: name)
            ) do
        assert Receiver.whereis(name) == nil
        :ok = Agent.stop(name)
      end
    end

    test "returns its argument when passed a registered receiver pid", %{pid: pid} do
      assert Receiver.whereis(pid) == pid
    end

    property "returns nil when passed a pid not registered as a receiver" do
      check all(
              name <- atom(:alias),
              name != Test,
              {:ok, pid} = Agent.start_link(fn -> nil end, name: name)
            ) do
        assert Receiver.whereis(pid) == nil
        :ok = Agent.stop(name)
      end
    end
  end
end
