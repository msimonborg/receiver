defmodule ExUnit.StartLinkTest do
  use ExUnit.Case

  defmodule(One, do: use(Receiver))
  defmodule(Two, do: use(Receiver, as: :backup))
  defmodule(Three, do: use(Receiver, name: LockBox))
  defmodule(Four, do: def(initial_state(arg), do: %{locked: [arg]}))

  describe "start_link/1" do
    test "accepts a list with two elements" do
      {:ok, pid} = Receiver.start_link([One, fn -> :received end])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      assert Agent.get(pid, & &1) == :received
      :ok = Agent.stop(pid)
    end

    test "accepts a list with three elements" do
      {:ok, pid} = Receiver.start_link([Two, fn -> :received end, [as: :backup]])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      assert Receiver.whereis({Two, :backup}) == pid
      :ok = Agent.stop(pid)
    end

    test "accepts a list with four elements" do
      {:ok, pid} = Receiver.start_link([One, Four, :initial_state, [:box]])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      assert Agent.get(pid, fn %{locked: [h | t]} -> {h, t} end) == {:box, []}
      :ok = Agent.stop(pid)
    end

    test "accepts a list with five elements" do
      {:ok, pid} = Receiver.start_link([Three, Four, :initial_state, [:box], [name: LockBox]])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      assert Receiver.whereis(LockBox) == pid
      :ok = Agent.stop(pid)
    end
  end
end
