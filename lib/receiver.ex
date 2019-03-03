defmodule Receiver do
  @moduledoc """
  Conveniences for creating processes that hold state.

  A simple wrapper around an `Agent` that reduces boilerplate code and makes it easy to store
  state in a separate supervised process.

  # Use cases

    * Creating a "stash" to persist process state across restarts. See [example](#stash) below.

    * Storing persistent process state outside of the worker process, or as a shared repository
    for multiple processes.

    * Testing higher order functions. By passing a function call to a `Receiver` process into a higher
    order function you can test if the function is executed as intended by checking the change in state.
    See [example](#testing) below.

  ## <a name="stash"></a>Example

      defmodule Counter do
        use GenServer
        use Receiver, as: :stash

        def start_link(arg) do
          GenServer.start_link(__MODULE__, arg, name: __MODULE__)
        end

        def increment(num) do
          GenServer.cast(__MODULE__, {:increment, num})
        end

        def get do
          GenServer.call(__MODULE__, :get)
        end

        # The stash is started with the initial state of the counter. If the stash is already
        # started when `start_stash/1` is called then its state will not change. The current state
        # of the stash is returned as the initial counter state whenever the counter is started.
        def init(arg) do
          start_stash(fn -> arg end)
          {:ok, get_stash()}
        end

        def handle_cast({:increment, num}, state) do
          {:noreply, state + num}
        end

        def handle_call(:get, _from, state) do
          {:reply, state, state}
        end

        # The stash is updated to the current counter state before the counter exits.
        # This state will be stored for use as the initial state of the counter when
        # it restarts, allowing the state to persist in the event of failure.
        def terminate(_reason, state) do
          update_stash(fn _ -> state end)
        end
      end

  The line `use Receiver, as: :stash` creates a named `Agent` using the `:via` semantics of the `Registry` module.
  The stash is supervised in the `Receiver` application supervision tree, not in your own application's. It also
  defines the following *private* client functions in the `Counter` module:

    * `start_stash/0` - Defaults the inital state to an empty list.
    * `start_stash/1` - Expects an anonymous function that will return the initial state when called.
    * `start_stash/3` - Expects a module, function name, and list of args that will return the initial state
    when called.
    * `stop_stash/2` - Optional `reason` and `timeout` args. See `Agent.stop/3` for more information.
    * `get_stash/0` - Returns the current state of the stash.
    * `update_stash/1` - Updates the state of the stash. Expects an anonymous function that receives
    the current state as an argument and returns the updated state.

  If no `:as` option were given in this example then the default function names are used:

    * `start_receiver/0`
    * `start_receiver/1`
    * `start_receiver/3`
    * `stop_receiver/2`
    * `get_receiver/0`
    * `update_receiver/1`

  See more detail on the generated functions in the [client functions](#client-functions) section below.

  The `Counter` can now be supervised and its state will be isolated from failure and persisted across restarts.

      # Start the counter under a supervisor
      {:ok, _pid} = Supervisor.start_link([{Counter, 0}], strategy: :one_for_one)

      # Get the state of the counter
      Counter.get()
      #=> 0

      # Increment the counter
      Counter.increment(2)
      #=> :ok

      # Get the updated state of the counter
      Counter.get()
      #=> 2

      # Stop the counter, initiating a restart
      GenServer.stop(Counter)
      #=> :ok

      # Get the counter state, which was persisted across restarts
      Counter.get()
      #=> 2

  ## <a name="client-functions"></a>Client Functions

  When we `use Receiver, as: :stash` above, the following private function definitions
  are automatically generated inside the `Counter` module:

      defp start_stash do
        Receiver.start(__MODULE__, :stash, fn -> [] end)
      end

      defp start_stash(fun) when is_function(fun) do
        Receiver.start(__MODULE__, :stash, fun)
      end

      defp start_stash(module, fun, args) do
        Receiver.start(__MODULE__, :stash, module, fun, args)
      end

      defp stop_stash(reason \\ :normal, timeout \\ :infinity) do
        Receiver.stop(__MODULE__, :stash, reason, timeout)
      end

      defp get_stash do
        Receiver.get(__MODULE__, :stash)
      end

      defp update_stash(fun) when is_function(fun) do
        Receiver.update(__MODULE__, :stash, fun)
      end

  These are private so the stash cannot easily be started, stopped, or updated from outside the counter process.
  A receiver can always be manipulated by calling the `Receiver` functions directly
  i.e. `Receiver.update(Counter, :stash, & &1 + 1)`, but in many cases these functions should be used with
  caution to avoid race conditions.

  ## A note on callbacks

  The first argument to all of the callbacks is the name of the receiver. This will either be the atom passed to
  the `:as` option or the default name `:receiver`. The intent is to avoid any naming collisions with other `handle_*`
  callbacks. All of the callbacks are invoked within the calling process, not the receiver process.

  ## <a name="testing"></a>Usage in testing

  A receiver can be used to test higher order functions by using it in an ExUnit test case and passing
  the `test: true` option. Consider the following example:

      defmodule Worker do
        def perform_complex_work(val, fun) do
          val
          |> do_some_calculation()
          |> fun.()
          |> do_other_calculation()
        end

        def do_some_calculation(val) do
          # perform work
        end

        def do_other_calculation(val) do
          # perform other work
        end
      end

      defmodule ExUnit.WorkerTest do
        use ExUnit.Case
        use Receiver, test: true

        setup do
          start_receiver()
        end

        def register(x) do
          update_receiver(fn _ -> x end)
        end

        test "it does the work in stages with help from an anonymous function" do
          assert get_receiver() == 0

          result = Worker.perform_complex_work(100, fn x -> register(x) end)
          receiver = get_receiver()

          assert Worker.do_some_calculation(100) == receiver
          assert Worker.do_other_calculation(receiver) == result
        end
      end

  When the `:test` option is set to `true` within a module using `ExUnit.Case`, you can call the `start_receiver`
  functions within a `setup` block, delegating to `ExUnit.Callbacks.start_supervised/2`. This will start the
  receiver as a supervised process under the test supervisor, automatically starting and shutting it down
  between tests to clean up state. This can help you test that your higher order functions are executing with
  the correct arguments and returning the expected results.
  """

  @typedoc "The receiver name"
  @type receiver :: :receiver | atom

  @typedoc "Return values of `start/3` and `start/5`"
  @type on_start :: DynamicSupervisor.on_start_child()

  @typedoc "A list of function arguments"
  @type args :: [term]

  @doc """
  Invoked in the calling process after the receiver is started. `start/3` or `start/5` will block until it returns.

  `pid` is the PID of the receiver process, `state` is the starting state of the receiver after the initializing
  function is called.

  If the receiver was already started when `start/3` or `start/5` was called then the callback will not be invoked.

  The return value is ignored.
  """
  @callback handle_start(receiver, pid, state :: term) :: term

  @callback handle_stop(receiver, reason :: term, state :: term) :: term

  @callback handle_get(receiver, state :: term) :: {:reply, any} | :noreply

  @callback handle_update(receiver, old_state :: term, state :: term) :: term

  @optional_callbacks handle_start: 3,
                      handle_stop: 3,
                      handle_get: 2,
                      handle_update: 3

  @spec start(module, receiver, fun) :: on_start
  def start(module, receiver \\ :receiver, fun) when is_function(fun) do
    do_start(module, receiver, [fun])
  end

  @spec start(module, receiver, module, atom, args) :: on_start
  def start(module, receiver \\ :receiver, mod, fun, args) when is_atom(mod) and is_atom(fun) and is_list(args) do
    do_start(module, receiver, [mod, fun, args])
  end

  defp do_start(module, receiver, args) do
    child = {Receiver.Server, args ++ [name: registered_name(module, receiver)]}
    case DynamicSupervisor.start_child(Receiver.Sup, child) do
      {:ok, pid} ->
        apply(module, :handle_start, [receiver, pid, get(module, receiver)])
        {:ok, pid}

      result -> result
    end
  end

  @spec get(module, receiver | fun(any)) :: any
  def get(module, receiver \\ :receiver)

  def get(module, fun) when is_function(fun), do: do_get(module, fun)

  def get(module, receiver), do: do_get(module, receiver, & &1)

  @spec get(module, receiver, fun(any)) :: any
  def get(module, receiver, fun) when is_function(fun), do: do_get(module, receiver, fun)

  defp do_get(module, receiver \\ :receiver, fun) do
    state = Agent.get(registered_name(module, receiver), fun)
    case apply(module, :handle_get, [receiver, state]) do
      {:reply, result} -> result
      :noreply -> state
    end
  end

  @spec update(module, receiver, fun(any)) :: :ok
  def update(module, receiver \\ :receiver, fun) do
    {old_state, new_state} = Agent.get_and_update(registered_name(module, receiver), fn old ->
      new = fun.(old)
      {{old, new}, new}
    end)

    apply(module, :handle_update, [receiver, old_state, new_state])
  end

  @spec stop(module, receiver, reason :: term, timeout) :: :ok
  def stop(module, receiver \\ :receiver, reason \\ :normal, timeout \\ :infinity) do
    state = Agent.get(registered_name(module, receiver), & &1)
    res = Agent.stop(registered_name(module, receiver), reason, timeout)
    apply(module, :handle_stop, [receiver, reason, state])
    res
  end

  defp registered_name(module, receiver) do
    {:via, Registry, {Receiver.Registry, [module, receiver]}}
  end

  defmacro __using__(opts) do
    {name, opts} = Keyword.pop(opts, :as, :receiver)
    {test, _} = Keyword.pop(opts, :test, false)

    registered_name = Macro.escape(registered_name(__CALLER__.module, name))

    quote location: :keep, bind_quoted: [name: name, test: test, registered_name: registered_name] do
      @behaviour Receiver

      if test do
        defp unquote(:"start_#{name}")() do
          start_supervised({Receiver.Server, [fn -> [] end, unquote(Macro.escape(registered_name))]})
        end

        defp unquote(:"start_#{name}")(fun) when is_function(fun) do
          start_supervised({Receiver.Server, [fun, name: unquote(Macro.escape(registered_name))]})
        end

        defp unquote(:"start_#{name}")(module, fun, args) do
          start_supervised({Receiver.Server, [module, fun, args, name: unquote(Macro.escape(registered_name))]})
        end
      else
        defp unquote(:"start_#{name}")() do
          Receiver.start(__MODULE__, unquote(name), fn -> [] end)
        end

        defp unquote(:"start_#{name}")(fun) when is_function(fun) do
          Receiver.start(__MODULE__, unquote(name), fun)
        end

        defp unquote(:"start_#{name}")(module, fun, args) do
          Receiver.start(__MODULE__, unquote(name), module, fun, args)
        end
      end

      defp unquote(:"stop_#{name}")(reason \\ :normal, timeout \\ :infinity) do
        Receiver.stop(__MODULE__, unquote(name), reason, timeout)
      end

      defp unquote(:"get_#{name}")() do
        Receiver.get(__MODULE__, unquote(name))
      end

      defp unquote(:"update_#{name}")(fun) when is_function(fun) do
        Receiver.update(__MODULE__, unquote(name), fun)
      end

      def handle_stop(unquote(name), reason, state), do: :ok

      def handle_start(unquote(name), pid, state), do: :ok

      def handle_get(unquote(name), state), do: :noreply

      def handle_update(unquote(name), old_state, new_state), do: :ok
    end
  end
end
