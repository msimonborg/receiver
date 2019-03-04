defmodule Receiver do
  @moduledoc ~S"""
  Conveniences for creating processes that hold state.

  A simple wrapper around an `Agent` that reduces boilerplate code and makes it easy to store
  state in a separate supervised process.

  # Use cases

    * Creating a "stash" to persist process state across restarts. See [example](#stash) below.

    * Application or server configuration. See [example](#config) below.

    * Storing mutable state outside of a worker process, or as a shared repository
    for multiple processes running the same module code.

    * Testing higher order functions. By passing a function call to a `Receiver` process into a higher
    order function you can test if the function is executed as intended by checking the change in state.
    See [example](#testing) below.

  ## <a name="stash"></a>Using as a stash

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
    * `get_stash/1` - Expects an anonymous function that accepts a single argument. The state of the stash
    is passed to the anonymous function, and the result of the function is returned.
    * `update_stash/1` - Updates the state of the stash. Expects an anonymous function that receives
    the current state as an argument and returns the updated state.
    * `get_and_update_stash/1` - Gets and updates the stash. Expects an anonymous function that receives the
    current state as an argument and returns a two element tuple, the first element being the value to
    return, the second element is the updated state.

  If no `:as` option were given in this example then the default function names are used:

    * `start_receiver/0`
    * `start_receiver/1`
    * `start_receiver/3`
    * `stop_receiver/2`
    * `get_receiver/0`
    * `get_receiver/1`
    * `update_receiver/1`
    * `get_and_update_receiver/1`

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

  ## <a name="client-functions"></a>Client functions

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

      defp get_and_update_stash(fun) when is_function(fun) do
        Receiver.get_and_update(__MODULE__, :stash, fun)
      end

  These are private so the stash cannot easily be started, stopped, or updated from outside the counter process.
  A receiver can always be manipulated by calling the `Receiver` functions directly
  i.e. `Receiver.update(Counter, :stash, & &1 + 1)`, but in many cases these functions should be used with
  caution to avoid race conditions.

  ## <a name="config"></a>Using as a configuration store

  A `Receiver` can be used to store application configuration, and even be initialized
  at startup. Since the receiver processes are supervised in a separate application
  that is a dependency of yours, it will already be ready to start even before your
  application's `start/2` callback has returned:

      defmodule MyApp do
        @doc false
        use Application
        use Receiver, as: :config

        def start(_app, _type) do
          start_config(fn ->
            Application.get_env(:my_app, :configuration, [setup: :default])
            |> Enum.into(%{})
          end)

          children = [
            MyApp.Worker,
            MyApp.Task
          ]

          Supervisor.start_link(children, strategy: :one_for_one, name: MyApp)
        end

        def config, do: get_config()
      end

  Now the configuration can be globally read with the public `MyApp.config/0`.

      MyApp.config()
      #=> %{setup: :default}

      MyApp.config.setup
      #=> :default

  ## <a name="testing"></a>Usage in testing

  A `Receiver` can also be used to test higher order functions by using it in an ExUnit test case and passing
  the `test: true` option. Consider the following example:

      defmodule Worker do
        def perform_complex_work(val, fun) do
          val
          |> do_some_work()
          |> fun.()
          |> do_other_work()
        end

        def do_some_work(val), do: :math.log(val)

        def do_other_work(val), do: :math.exp(val) |> :math.floor()
      end

      defmodule ExUnit.HigherOrderTest do
        use ExUnit.Case
        use Receiver, test: true

        setup do
          start_receiver(fn -> nil end)
          :ok
        end

        def register(x) do
          get_and_update_receiver(fn _ -> {x, x} end)
        end

        test "it does the work in stages with help from an anonymous function" do
          assert get_receiver() == nil

          result = Worker.perform_complex_work(1.0, fn x -> register(x) end)
          receiver = get_receiver()

          assert Worker.do_some_work(1.0) == receiver
          assert Worker.do_other_work(receiver) == result
        end
      end

  When the `:test` option is set to `true` within a module using `ExUnit.Case`, you can call the `start_receiver`
  functions within a `setup` block, delegating to `ExUnit.Callbacks.start_supervised/2`. This will start the
  receiver as a supervised process under the test supervisor, automatically starting and shutting it down
  between tests to clean up state. This can help you test that your higher order functions are executing with
  the correct arguments and returning the expected results.

  ## A note on callbacks

  The first argument to all of the callbacks is the name of the receiver. This will either be the atom passed to
  the `:as` option or the default name `:receiver`. The intent is to avoid any naming collisions with other `handle_*`
  callbacks. All of the callbacks are invoked within the calling process, not the receiver process.
  """

  @typedoc "The receiver name"
  @type receiver :: :receiver | atom

  @typedoc "Return values of `start/3` and `start/5`"
  @type on_start :: DynamicSupervisor.on_start_child()

  @typedoc "A list of function arguments"
  @type args :: [term]

  @typedoc "The receiver state"
  @type state :: term

  @doc """
  Invoked in the calling process after the receiver is started. `start/3` and `start/5` will block until it returns.

  `pid` is the PID of the receiver process, `state` is the starting state of the receiver after the initializing
  function is called.

  If the receiver was already started when `start/3` or `start/5` was called then the callback will not be invoked.

  The return value is ignored.
  """
  @callback handle_start(receiver, pid, state :: term) :: term

  @doc """
  Invoked in the calling process after the receiver is stopped. `stop/4` will block until it returns.

  `reason` is the exit reason, `state` is the receiver state at the time of shutdown. See `Agent.stop/3`
  for more information.

  The return value is ignored.
  """
  @callback handle_stop(receiver, reason :: term, state :: term) :: term

  @doc """
  Invoked in the calling process after a `get` request is sent to the receiver. `get/2` and `get/3`
  will block until it returns.

  `state` is the return value of the function passed to `get/2` or `get/3` and invoked in the receiver.
  With basic `get` functions this will be the current state of the receiver.

  Returning `{:reply, reply}` causes `reply` to be the return value of `get/2` and `get/3`
  (and the private `get_receiver` client functions).

  If `:noreply` is the return value then `state` will be the return value of `get/2` and `get/3`.
  This can be useful if action needs to be performed with the `state` value but there's no desire
  to return the results of those actions to the caller.
  """
  @callback handle_get(receiver, state :: term) :: {:reply, reply :: term} | :noreply

  @callback handle_update(receiver, old_state :: term, state) :: term

  @callback handle_get_and_update(receiver, return_val :: term, state) :: {:reply, reply :: term} | :noreply

  @optional_callbacks handle_start: 3,
                      handle_stop: 3,
                      handle_get: 2,
                      handle_update: 3,
                      handle_get_and_update: 3

  @spec start(module, receiver, (() -> term)) :: on_start
  def start(module, receiver \\ :receiver, fun) when is_function(fun, 0) do
    do_start(module, receiver, [fun])
  end

  @spec start(module, receiver, module, atom, args) :: on_start
  def start(module, receiver \\ :receiver, mod, fun, args)
      when is_atom(mod) and is_atom(fun) and is_list(args) do
    do_start(module, receiver, [mod, fun, args])
  end

  @spec do_start(module, receiver, args) :: on_start
  defp do_start(module, receiver, args) do
    child = {Receiver.Server, args ++ [name: registered_name(module, receiver)]}

    case DynamicSupervisor.start_child(Receiver.Sup, child) do
      {:ok, pid} ->
        apply(module, :handle_start, [receiver, pid, get(module, receiver)])
        {:ok, pid}

      result ->
        result
    end
  end

  @spec get(module, receiver | (state -> term)) :: term
  def get(module, receiver_or_fun \\ :receiver)

  def get(module, fun) when is_function(fun, 1), do: do_get(module, :receiver, fun)

  def get(module, receiver), do: do_get(module, receiver, & &1)

  @spec get(module, receiver, (state -> term)) :: term
  def get(module, receiver, fun) when is_function(fun, 1), do: do_get(module, receiver, fun)

  defp do_get(module, receiver, fun) do
    state = Agent.get(registered_name(module, receiver), fun)

    case apply(module, :handle_get, [receiver, state]) do
      {:reply, reply} -> reply
      :noreply -> state
    end
  end

  @spec update(module, receiver, (state -> state)) :: :ok
  def update(module, receiver \\ :receiver, fun) when is_function(fun, 1) do
    {old_state, new_state} =
      Agent.get_and_update(registered_name(module, receiver), fn old ->
        new = fun.(old)
        {{old, new}, new}
      end)

    apply(module, :handle_update, [receiver, old_state, new_state])
    :ok
  end

  @spec get_and_update(module, receiver, (state -> {term, state})) :: term
  def get_and_update(module, receiver \\ :receiver, fun) when is_function(fun, 1) do
    {return_val, new_state} =
      Agent.get_and_update(registered_name(module, receiver), fn old ->
        {return, new} = fun.(old)
        {{return, new}, new}
      end)

    case apply(module, :handle_get_and_update, [receiver, return_val, new_state]) do
      {:reply, reply} -> reply
      :noreply -> return_val
    end
  end

  @spec stop(module, receiver, reason :: term, timeout) :: :ok
  def stop(module, receiver \\ :receiver, reason \\ :normal, timeout \\ :infinity) do
    state = Agent.get(registered_name(module, receiver), & &1)
    with :ok <- Agent.stop(registered_name(module, receiver), reason, timeout) do
      apply(module, :handle_stop, [receiver, reason, state])
      :ok
    end
  end

  defp registered_name(module, receiver) do
    {:via, Registry, {Receiver.Registry, [module, receiver]}}
  end

  defmacro __using__(opts) do
    {name, opts} = Keyword.pop(opts, :as, :receiver)
    {test, _} = Keyword.pop(opts, :test, false)

    registered_name = Macro.escape(registered_name(__CALLER__.module, name))

    quote location: :keep,
          bind_quoted: [name: name, test: test, registered_name: registered_name] do
      @behaviour Receiver

      if test do
        defp unquote(:"start_#{name}")() do
          start_supervised(
            {Receiver.Server, [fn -> [] end, name: unquote(Macro.escape(registered_name))]}
          )
        end

        defp unquote(:"start_#{name}")(fun) when is_function(fun) do
          start_supervised({Receiver.Server, [fun, name: unquote(Macro.escape(registered_name))]})
        end

        defp unquote(:"start_#{name}")(module, fun, args) do
          start_supervised(
            {Receiver.Server, [module, fun, args, name: unquote(Macro.escape(registered_name))]}
          )
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

      defp unquote(:"get_#{name}")(fun) do
        Receiver.get(__MODULE__, unquote(name), fun)
      end

      defp unquote(:"update_#{name}")(fun) when is_function(fun) do
        Receiver.update(__MODULE__, unquote(name), fun)
      end

      defp unquote(:"get_and_update_#{name}")(fun) when is_function(fun) do
        Receiver.get_and_update(__MODULE__, unquote(name), fun)
      end

      defoverridable "start_#{name}": 0,
                     "start_#{name}": 1,
                     "start_#{name}": 3,
                     "stop_#{name}": 0,
                     "stop_#{name}": 1,
                     "stop_#{name}": 2,
                     "get_#{name}": 0,
                     "get_#{name}": 1,
                     "update_#{name}": 1,
                     "get_and_update_#{name}": 1

      @doc false
      def handle_stop(unquote(name), reason, state), do: :ok

      @doc false
      def handle_start(unquote(name), pid, state), do: :ok

      @doc false
      def handle_get(unquote(name), state), do: :noreply

      @doc false
      def handle_update(unquote(name), old_state, new_state), do: :ok

      @doc false
      def handle_get_and_update(unquote(name), return_val, new_state), do: :noreply

      defoverridable handle_stop: 3,
                     handle_start: 3,
                     handle_get: 2,
                     handle_update: 3,
                     handle_get_and_update: 3
    end
  end
end
