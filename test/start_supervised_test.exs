defmodule ExUnit.StartSupervisedTest do
  use ExUnit.Case

  defmodule(One, do: use(Receiver))
  defmodule(Two, do: use(Receiver, as: :backup))
  defmodule(Three, do: use(Receiver, name: LockBox))
  defmodule(Four, do: def(initial_state(arg), do: %{locked: [arg]}))

  describe "start_supervised/3" do
    test "accepts a callback module and funtion" do
      {:ok, pid} = Receiver.start_supervised(One, fn -> %{} end)
      assert pid in (Process.whereis(Receiver.Sup) |> Process.info() |> Keyword.get(:links))
      assert Receiver.get({One, :receiver}) == %{}
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, function, and options" do
      {:ok, pid} = Receiver.start_supervised(Two, fn -> %{} end, as: :backup)
      assert pid in (Process.whereis(Receiver.Sup) |> Process.info() |> Keyword.get(:links))
      assert Receiver.get({Two, :backup}) == %{}
      :ok = Agent.stop(pid)
    end
  end

  describe "start_supervised/5" do
    test "accepts a callback module and mfa" do
      {:ok, pid} = Receiver.start_supervised(One, Four, :initial_state, [:box])
      assert pid in (Process.whereis(Receiver.Sup) |> Process.info() |> Keyword.get(:links))
      assert Agent.get(pid, fn %{locked: [h | t]} -> {h, t} end) == {:box, []}
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, mfa, and opts" do
      {:ok, pid} = Receiver.start_supervised(Three, Four, :initial_state, [:box], name: LockBox)
      assert pid in (Process.whereis(Receiver.Sup) |> Process.info() |> Keyword.get(:links))
      assert Receiver.get(LockBox) == %{locked: [:box]}
      :ok = Agent.stop(pid)
    end
  end
end
