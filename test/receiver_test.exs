defmodule(One, do: use(Receiver))
defmodule(Two, do: use(Receiver, as: :backup))
defmodule(Three, do: use(Receiver, name: LockBox))
defmodule(Four, do: def(initial_state(arg), do: %{locked: [arg]}))

defmodule ReceiverTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  use ExUnitReceiver, as: :tester, name: Tester
  doctest Receiver

  describe "start functions" do
    setup do
      msg = "haven't sent any messages"
      start_supervised({Receiver, [One, fn -> msg end]})
      %{msg: msg}
    end

    property "aren't executed when receiver is already started", %{msg: msg} do
      check all val <- term() do
        me = self()
        {:error, {:already_started, _}} = Receiver.start(One, fn -> send(me, val) end)
        refute_receive(^val, 5)

        {:error, {:already_started, _}} = Receiver.start_link(One, fn -> send(me, val) end)
        refute_receive(^val, 5)

        {:error, {:already_started, _}} = Receiver.start_supervised(One, fn -> send(me, val) end)
        refute_receive(^val, 5)

        assert Receiver.get({One, :receiver}, & &1) == msg
      end
    end
  end

  describe "start/3" do
    test "accepts a callback module and funtion" do
      {:ok, pid} = Receiver.start(One, fn -> %{} end)
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, function, and options" do
      {:ok, pid} = Receiver.start(Two, fn -> %{} end, as: :backup)
      :ok = Agent.stop(pid)
    end

    test "returns an error tuple when the wrong receiver name is given" do
      {:error, {error, _}} = Receiver.start(One, fn -> [] end, as: :wrong)

      assert_raise(
        FunctionClauseError,
        "no function clause matching in One.handle_start/3",
        fn -> raise error end
      )

      assert Receiver.whereis({One, :wrong}) == nil
      assert Receiver.whereis({One, :receiver}) == nil
    end

    property "returns an error tuple when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        {:error, {error, _}} = Receiver.start(mod, fn -> %{} end)

        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_start/3 is undefined (module #{mod_to_s} is not available)",
          fn -> raise error end
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

    test "returns an error tuple when the wrong receiver name is given" do
      {:error, {error, _}} = Receiver.start(One, Four, :initial_state, [:box], as: :wrong)

      assert_raise(
        FunctionClauseError,
        "no function clause matching in One.handle_start/3",
        fn -> raise error end
      )

      assert Receiver.whereis({One, :wrong}) == nil
    end

    property "returns an error tuple when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        {:error, {error, _}} = Receiver.start(mod, Four, :initial_state, [:box])

        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_start/3 is undefined (module #{mod_to_s} is not available)",
          fn -> raise error end
        )
      end
    end
  end

  describe "start_link/1" do
    test "accepts a list with two elements" do
      {:ok, pid} = Receiver.start_link([One, fn -> :received end])
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a list with three elements" do
      {:ok, pid} = Receiver.start_link([Two, fn -> :received end, [as: :backup]])
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a list with four elements" do
      {:ok, pid} = Receiver.start_link([One, Four, :initial_state, [:box]])
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a list with five elements" do
      {:ok, pid} = Receiver.start_link([Three, Four, :initial_state, [:box], [name: LockBox]])
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end
  end

  describe "start_link/3" do
    test "accepts a callback module and funtion" do
      {:ok, pid} = Receiver.start_link(One, fn -> %{} end)
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, function, and options" do
      {:ok, pid} = Receiver.start_link(Two, fn -> %{} end, as: :backup)
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "returns an error tuple when the wrong receiver name is given" do
      {:error, {error, _}} = Receiver.start_link(One, fn -> [] end, as: :wrong)

      assert_raise(
        FunctionClauseError,
        "no function clause matching in One.handle_start/3",
        fn -> raise error end
      )

      assert Receiver.whereis({One, :wrong}) == nil
    end

    property "returns an error tuple a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        {:error, {error, _}} = Receiver.start_link(mod, fn -> %{} end)

        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_start/3 is undefined (module #{mod_to_s} is not available)",
          fn -> raise error end
        )
      end
    end
  end

  describe "start_link/5" do
    test "accepts a callback module and mfa" do
      {:ok, pid} = Receiver.start_link(One, Four, :initial_state, [:box])
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, mfa, and opts" do
      {:ok, pid} = Receiver.start_link(Three, Four, :initial_state, [:box], name: LockBox)
      assert self() in (pid |> Process.info() |> Keyword.get(:links)) == true
      :ok = Agent.stop(pid)
    end

    test "returns an error tuple when the wrong receiver name is given" do
      {:error, {error, _}} = Receiver.start_link(One, Four, :initial_state, [:box], as: :wrong)

      assert_raise(
        FunctionClauseError,
        "no function clause matching in One.handle_start/3",
        fn -> raise error end
      )

      assert Receiver.whereis({One, :wrong}) == nil
    end

    property "returns an error tuple when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        {:error, {error, _}} = Receiver.start_link(mod, Four, :initial_state, [:box])

        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_start/3 is undefined (module #{mod_to_s} is not available)",
          fn -> raise error end
        )
      end
    end
  end

  describe "start_supervised/3" do
    test "accepts a callback module and funtion" do
      {:ok, pid} = Receiver.start_supervised(One, fn -> %{} end)
      assert pid in (Receiver.Sup |> Process.whereis() |> Process.info() |> Keyword.get(:links))
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, function, and options" do
      {:ok, pid} = Receiver.start_supervised(Two, fn -> %{} end, as: :backup)
      assert pid in (Receiver.Sup |> Process.whereis() |> Process.info() |> Keyword.get(:links))
      :ok = Agent.stop(pid)
    end

    test "returns an error tuple when the wrong receiver name is given" do
      {:error, {error, _}} = Receiver.start_supervised(One, fn -> [] end, as: :wrong)

      assert_raise(
        FunctionClauseError,
        "no function clause matching in One.handle_start/3",
        fn -> raise error end
      )

      assert Receiver.whereis({One, :wrong}) == nil
    end

    property "returns an error tuple when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        {:error, {error, _}} = Receiver.start_supervised(mod, fn -> [] end)

        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_start/3 is undefined (module #{mod_to_s} is not available)",
          fn -> raise error end
        )
      end
    end
  end

  describe "start_supervised/5" do
    test "accepts a callback module and mfa" do
      {:ok, pid} = Receiver.start_supervised(One, Four, :initial_state, [:box])
      assert pid in (Receiver.Sup |> Process.whereis() |> Process.info() |> Keyword.get(:links))
      :ok = Agent.stop(pid)
    end

    test "accepts a callback module, mfa, and opts" do
      {:ok, pid} = Receiver.start_supervised(Three, Four, :initial_state, [:box], name: LockBox)
      assert pid in (Receiver.Sup |> Process.whereis() |> Process.info() |> Keyword.get(:links))
      :ok = Agent.stop(pid)
    end

    test "returns an error tuple when the wrong receiver name is given" do
      {:error, {error, _}} =
        Receiver.start_supervised(One, Four, :initial_state, [:box], as: :wrong)

      assert_raise(
        FunctionClauseError,
        "no function clause matching in One.handle_start/3",
        fn -> raise error end
      )

      assert Receiver.whereis({One, :wrong}) == nil
    end

    property "returns an error tuple when a bad callback module is given" do
      check all mod <- atom(:alias),
                mod not in [One, Two, Three, Four],
                mod_to_s = String.trim("#{mod}", "Elixir.") do
        {:error, {error, _}} = Receiver.start_supervised(mod, Four, :initial_state, [:box])

        assert_raise(
          UndefinedFunctionError,
          "function #{mod_to_s}.handle_start/3 is undefined (module #{mod_to_s} is not available)",
          fn -> raise error end
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

    property "raises a Receiver.NotFoundError with an invalid receiver input" do
      check all module <- atom(:alias),
                receiver <- atom(:alphanumeric),
                name <- atom(:alias),
                module != __MODULE__,
                receiver != :tester,
                name != Tester do
        assert_raise Receiver.NotFoundError, fn -> Receiver.get({module, receiver}) end
        assert_raise Receiver.NotFoundError, fn -> Receiver.get(name) end
      end
    end

    property "returns a modified value without updating state" do
      check all val <- term() do
        assert Receiver.get(Tester, fn state -> {state, val} end) == {:test, val}
        assert Receiver.get(Tester) == :test
      end
    end
  end

  describe "update/2" do
    setup do
      {:ok, pid} = start_tester(fn -> :test end)
      %{pid: pid}
    end

    test "accepts a receiver name in the form of `{module, atom}`" do
      assert Receiver.update({__MODULE__, :tester}, & &1) == :ok
    end

    test "accepts a receiver name in the form of an atom" do
      assert Receiver.update(Tester, & &1) == :ok
    end

    test "accepts a pid", %{pid: pid} do
      assert Receiver.update(pid, & &1) == :ok
    end

    property "raises a Receiver.NotFoundError with an invalid receiver input" do
      check all module <- atom(:alias),
                receiver <- atom(:alphanumeric),
                name <- atom(:alias),
                module != __MODULE__,
                receiver != :tester,
                name != Tester do
        assert_raise Receiver.NotFoundError, fn -> Receiver.update({module, receiver}, & &1) end
        assert_raise Receiver.NotFoundError, fn -> Receiver.update(name, & &1) end
      end
    end

    property "updates the state with the return value of the anonymous function" do
      check all val <- term() do
        assert Receiver.update(Tester, fn _state -> val end) == :ok
        assert Receiver.get(Tester) == val
      end
    end
  end

  describe "get_and_update/2" do
    setup do
      {:ok, pid} = start_tester(fn -> :test end)
      %{pid: pid}
    end

    test "accepts a receiver name in the form of `{module, atom}`" do
      assert Receiver.get_and_update({__MODULE__, :tester}, &{&1, &1}) == :test
    end

    test "accepts a receiver name in the form of an atom" do
      assert Receiver.get_and_update(Tester, &{&1, &1}) == :test
    end

    test "accepts a pid", %{pid: pid} do
      assert Receiver.get_and_update(pid, &{&1, &1}) == :test
    end

    property "raises a Receiver.NotFoundError with an invalid receiver input" do
      check all module <- atom(:alias),
                receiver <- atom(:alphanumeric),
                name <- atom(:alias),
                module != __MODULE__,
                receiver != :tester,
                name != Tester do
        assert_raise Receiver.NotFoundError, fn ->
          Receiver.get_and_update({module, receiver}, & &1)
        end

        assert_raise Receiver.NotFoundError, fn -> Receiver.get_and_update(name, & &1) end
      end
    end

    property "gets and updates the state with the return value of the anonymous function" do
      check all new <- term() do
        previous = Receiver.get(Tester)
        assert Receiver.get_and_update(Tester, fn previous -> {previous, new} end) == previous
        assert Receiver.get(Tester) == new
      end
    end
  end

  describe "stop/1" do
    setup do
      {:ok, pid} = start_tester(fn -> :test end)
      %{pid: pid}
    end

    test "accepts a receiver name in the form of `{module, atom}`" do
      assert Receiver.stop({__MODULE__, :tester}) == :ok
    end

    test "accepts a receiver name in the form of an atom" do
      assert Receiver.stop(Tester) == :ok
    end

    test "accepts a pid", %{pid: pid} do
      assert Receiver.stop(pid) == :ok
    end

    property "raises a Receiver.NotFoundError with an invalid receiver input" do
      check all module <- atom(:alias),
                receiver <- atom(:alphanumeric),
                name <- atom(:alias),
                module != __MODULE__,
                receiver != :tester,
                name != Tester do
        assert_raise Receiver.NotFoundError, fn -> Receiver.stop({module, receiver}) end
        assert_raise Receiver.NotFoundError, fn -> Receiver.stop(name) end
      end
    end

    property "terminates a running Receiver" do
      check all name <- atom(:alias),
                name != Tester do
        {:ok, pid} = Receiver.start_link(One, fn -> [] end, name: name)
        assert Process.whereis(name) == pid
        Receiver.stop(name)
        assert Process.whereis(name) == nil
        assert Process.alive?(pid) == false
      end
    end
  end
end
