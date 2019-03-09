defmodule ExUnit.ReceiverTest do
  use ExUnit.Case
  use Receiver, test: true, as: :tester, name: Tester
  doctest Receiver

  setup do
    {:ok, pid} = start_tester(fn -> :test end)
    %{pid: pid}
  end

  describe "get/1" do
    test "accepts a receiver name in the form of `{module, atom}`" do
      assert Receiver.get({__MODULE__, :tester}) == :test
    end

    test "accepts a receiver name in the form of an atom" do
      assert Receiver.get(Tester) == :test
    end

    test "accepts a pid", %{pid: pid} do
      assert Receiver.get(pid) == :test
    end
  end
end
