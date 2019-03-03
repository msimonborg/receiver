defmodule ExUnit.OverridableTest do
  use ExUnit.Case
  use Receiver

  defp get_receiver(fun) do
    {:ok, super(fun)}
  end

  defp start_receiver() do
    start_receiver(:ready)
  end

  defp start_receiver(value) do
    super(fn -> value end)
  end

  defp update_receiver(value) do
    super(fn state -> "updated from #{state}: " <> value end)
  end

  defp stop_receiver() do
    case super() do
      :ok -> :stopped
    end
  end

  describe "get_receiver" do
    setup do
      start_receiver()
      on_exit(fn -> stop_receiver() end)
    end

    test "is overridable and can call super" do
      assert get_receiver(fn state -> Atom.to_string(state) end) == {:ok, "ready"}
    end
  end

  describe "start_receiver" do
    setup do
      on_exit(fn -> stop_receiver() end)
    end

    test "is overridable and can call super" do
      start_receiver(:ok)

      assert get_receiver() == :ok
    end
  end

  describe "update_receiver" do
    setup do
      start_receiver()
      on_exit(fn -> stop_receiver() end)
    end

    test "is overridable and can call super" do
      update_receiver("hold")
      assert get_receiver() == "updated from ready: hold"
    end
  end

  describe "stop_receiver" do
    test "is overridable and can call super" do
      start_receiver()
      assert stop_receiver() == :stopped
    end
  end
end
