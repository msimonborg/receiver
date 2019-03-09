defmodule ExUnit.ReceiverTest do
  use ExUnit.Case
  use ExUnitProperties
  use Receiver, test: true, as: :tester, name: Tester
  doctest Receiver

  defmodule(One, do: use(Receiver))
  defmodule(Two, do: use(Receiver, as: :backup))
  defmodule(Three, do: use(Receiver, name: LockBox))
  defmodule(Four, do: def(initial_state(arg), do: %{locked: [arg]}))

  describe "start/3" do
    test "accepts a callback module and funtion" do
      {:ok, pid} = Receiver.start(One, fn -> %{} end)
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, function, and options" do
      {:ok, pid} = Receiver.start(Two, fn -> %{} end, as: :backup)
      :ok = Agent.stop(pid)
    end

    property "raises an exception when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_stop/3 is undefined (module #{mod_to_s} is not available)",
          fn -> Receiver.start(mod, fn -> %{} end) end
        )
      end
    end
  end

  describe "start/5" do
    test "accepts a callback module and mfa" do
      {:ok, pid} = Receiver.start(One, Four, :initial_state, [:box])
      assert Agent.get(pid, & &1) == %{locked: [:box]}
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, mfa, and opts" do
      {:ok, pid} = Receiver.start(Three, Four, :initial_state, [:box], name: LockBox)
      assert Process.whereis(LockBox) == pid
      :ok = Agent.stop(pid)
    end

    property "raises an exception when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_stop/3 is undefined (module #{mod_to_s} is not available)",
          fn -> Receiver.start(mod, Four, :initial_state, [:box]) end
        )
      end
    end
  end

  describe "start_link/1" do
    test "accepts a list with two elements" do
      {:ok, pid} = Receiver.start_link([One, fn -> :received end])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a list with three elements" do
      {:ok, pid} = Receiver.start_link([Two, fn -> :received end, [as: :backup]])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a list with four elements" do
      {:ok, pid} = Receiver.start_link([One, Four, :initial_state, [:box]])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a list with five elements" do
      {:ok, pid} = Receiver.start_link([Three, Four, :initial_state, [:box], [name: LockBox]])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end
  end

  describe "start_link/3" do
    test "accepts a callback module and funtion" do
      {:ok, pid} = Receiver.start_link(One, fn -> %{} end)
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, function, and options" do
      {:ok, pid} = Receiver.start_link(Two, fn -> %{} end, as: :backup)
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    property "raises an exception when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_stop/3 is undefined (module #{mod_to_s} is not available)",
          fn -> Receiver.start_link(mod, fn -> %{} end) end
        )
      end
    end
  end

  describe "start_link/5" do
    test "accepts a callback module and mfa" do
      {:ok, pid} = Receiver.start_link(One, Four, :initial_state, [:box])
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, mfa, and opts" do
      {:ok, pid} = Receiver.start_link(Three, Four, :initial_state, [:box], name: LockBox)
      assert self() in (Process.info(pid) |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    property "raises an exception when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_stop/3 is undefined (module #{mod_to_s} is not available)",
          fn -> Receiver.start_link(mod, Four, :initial_state, [:box]) end
        )
      end
    end
  end

  describe "get/1 and get/2" do
    setup do
      {:ok, pid} = start_tester(fn -> :test end)
      %{pid: pid}
    end

    test "accepts a receiver name in the form of `{module, atom}`" do
      assert Receiver.get({__MODULE__, :tester}) == :test
    end

    test "accepts a receiver name in the form of an atom" do
      assert Receiver.get(Tester) == :test
    end

    test "accepts a pid", %{pid: pid} do
      assert Receiver.get(pid) == :test
    end

    property "raises an ArgumentError with an invalid receiver input" do
      check all module <- atom(:alias),
                receiver <- atom(:alphanumeric),
                name <- atom(:alias),
                module != __MODULE__,
                receiver != :tester,
                name != Tester do
        assert_raise ArgumentError, fn -> Receiver.get({module, receiver}) end
        assert_raise ArgumentError, fn -> Receiver.get(name) end
      end
    end

    property "returns a modified value without updating state" do
      check all val <- term() do
        assert Receiver.get(Tester, fn state -> {state, val} end) == {:test, val}
        assert Receiver.get(Tester) == :test
      end
    end
  end
end
