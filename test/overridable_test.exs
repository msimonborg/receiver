defmodule ExUnit.OverridableTest do
  use ExUnit.Case
  use Receiver, test: true

  defp get_receiver() do
    {:ok, Receiver.get(__MODULE__, :receiver)}
  end

  defp get_receiver(fun) do
    {:ok, super(fun)}
  end

  setup do
    start_receiver()
    :ok
  end

  describe "get_receiver" do
    test "is overridable" do
      assert get_receiver() == {:ok, []}
    end

    test "can call super" do
      assert get_receiver(& &1) == {:ok, []}
    end
  end
end
