defmodule ExUnit.StartTest do
  use ExUnit.Case

  defmodule(One, do: use(Receiver))
  defmodule(Two, do: use(Receiver, as: :backup))
  defmodule(Three, do: use(Receiver, name: LockBox))
  defmodule(Four, do: def(initial_state(arg), do: %{locked: [arg]}))

  describe "start/3" do
    test "accepts a callback module and funtion" do
      {:ok, pid} = Receiver.start(One, fn -> %{} end)
      assert Receiver.whereis({One, :receiver}) == pid
      assert Receiver.get({One, :receiver}) == %{}
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, function, and options" do
      {:ok, pid} = Receiver.start_link(Two, fn -> %{} end, as: :backup)
      assert Receiver.whereis({Two, :backup}) == pid
      assert Receiver.get({Two, :backup}) == %{}
      :ok = Agent.stop(pid)
    end
  end

  describe "start/5" do
    test "accepts a callback module and mfa" do
      {:ok, pid} = Receiver.start(One, Four, :initial_state, [:box])
      assert Receiver.whereis({One, :receiver}) == pid
      assert Agent.get(pid, fn %{locked: [h | t]} -> {h, t} end) == {:box, []}
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, mfa, and opts" do
      {:ok, pid} = Receiver.start(Three, Four, :initial_state, [:box], name: LockBox)
      assert Receiver.whereis(LockBox) == pid
      assert Receiver.get(LockBox) == %{locked: [:box]}
      :ok = Agent.stop(pid)
    end
  end
end
