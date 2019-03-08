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
        Receiver.start_supervised({__MODULE__, :stash}, fn -> [] end)
      end

      defp start_stash(fun) when is_function(fun, 0) do
        Receiver.start_supervised({__MODULE__, :stash}, fun)
      end

      defp start_stash(module, fun, args) do
        Receiver.start_supervised({__MODULE__, :stash}, module, fun, args)
      end

      defp stop_stash(reason \\ :normal, timeout \\ :infinity) do
        Receiver.stop({__MODULE__, :stash}, reason, timeout)
      end

      defp get_stash do
        Receiver.get({__MODULE__, :stash})
      end

      defp get_stash(fun) when is_function(fun, 1) do
        Receiver.get({__MODULE__, :stash}, fun)
      end

      defp update_stash(fun) when is_function(fun, 1) do
        Receiver.update({__MODULE__, :stash}, fun)
      end

      defp get_and_update_stash(fun) when is_function(fun, 1) do
        Receiver.get_and_update({__MODULE__, :stash}, fun)
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
  use Agent, restart: :transient

  @typedoc "The receiver name"
  @type receiver :: atom | {module, atom} | pid

  @typedoc "Return values of `start_supervised/3` and `start_supervised/5`"
  @type on_start_supervised :: DynamicSupervisor.on_start_child()

  @typedoc "Return values of `start/3` and `start/5`"
  @type on_start :: Agent.on_start()

  @typedoc "A list of function arguments"
  @type args :: [term]

  @typedoc "A list of arguments accepted by `start*` functions"
  @type start_args ::
          [module | fun]
          | [module | fun | options]
          | [module | atom | args]
          | [module | atom | args | options]

  @typedoc "Option values used by the `start*` functions"
  @type option :: {:as, atom} | {:name, atom}

  @typedoc "Options used by the `start*` functions"
  @type options :: [option]

  @typedoc "The receiver state"
  @type state :: term

  @typedoc "The registered name of a receiver"
  @type registered_name :: {:via, Registry, {Receiver.Registry, {module, atom}}}

  @typedoc "The receiver attributes required for successful start and registration"
  @type start_attrs :: %{
          module: module,
          receiver: atom,
          name: atom | registered_name,
          initial_state: term
        }

  @doc """
  Invoked in the calling process after the receiver is started. `start/3` and `start/5` will block until it returns.

  `pid` is the PID of the receiver process, `state` is the starting state of the receiver after the initializing
  function is called.

  If the receiver was already started when `start/3` or `start/5` was called then the callback will not be invoked.

  The return value is ignored.
  """
  @callback handle_start(atom, pid, state) :: term

  @doc """
  Invoked in the calling process after the receiver is stopped. `stop/4` will block until it returns.

  `reason` is the exit reason, `state` is the receiver state at the time of shutdown. See `Agent.stop/3`
  for more information.

  The return value is ignored.
  """
  @callback handle_stop(atom, reason :: term, state) :: term

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
  @callback handle_get(atom, state) :: {:reply, reply :: term} | :noreply

  @callback handle_update(atom, old_state :: state, state) :: term

  @callback handle_get_and_update(atom, return_val :: term, state) ::
              {:reply, reply :: term} | :noreply

  @optional_callbacks handle_start: 3,
                      handle_stop: 3,
                      handle_get: 2,
                      handle_update: 3,
                      handle_get_and_update: 3

  @doc """
  Starts a new receiver without links (outside of a supervision tree).

  See `start_link/3` for more information.

  ## Examples

      {:ok, _} = Receiver.start(Example, fn -> %{} end)
      Receiver.get({Example, :receiver})
      #=> %{}

      {:ok, _} = Receiver.start(Example, fn -> %{} end, name: Example.Map)
      Receiver.get(Example.Map)
      #=> %{}

  """
  @spec start(module, (() -> term), options) :: on_start
  def start(module, fun, opts \\ [])
      when is_atom(module) and is_function(fun, 0) and is_list(opts) do
    do_start(module, [fun], opts)
  end

  @spec start(module, module, atom, args, options) :: on_start
  def start(module, mod, fun, args, opts \\ [])
      when is_atom(module) and is_atom(mod) and is_atom(fun) and is_list(args) and is_list(opts) do
    do_start(module, [mod, fun, args], opts)
  end

  @spec do_start(module, args, options) :: on_start
  defp do_start(module, args, opts) do
    attrs = get_start_attrs(module, args, opts)

    Agent.start(initialization_func(attrs), name: attrs.name)
    |> invoke_handle_start_callback(module, attrs)
  end

  @doc """
  Starts a `Receiver` process linked to the current process.

  This is the function used to start a receiver as part of a supervision tree. It accepts a list
  containing from two to five arguments.

  Usually this should be used to build a child spec in your supervision tree.

  ## Examples

      children = [
        {Receiver, [One, fn -> 1 end]},
        {Receiver, [Two, fn -> 2 end, [name: Two]]},
        {Receiver, [Three, Kernel, :+, [2, 1]]},
        {Receiver, [Four, Kernerl, :+, [2, 2], [name: Four]]}
      ]

      Supervisor.start_link(children, strategy: one_for_one)

  Only use this is if you really need to supervise your own receiver. In most cases you should
  use the `start_supervised*` functions to start a supervised receiver dynamically in an isolated
  application. See `start_supervised/3` and `start_supervised/5` for more information.
  """
  @spec start_link(start_args) :: on_start
  def start_link(list_of_args) when is_list(list_of_args) do
    apply(__MODULE__, :start_link, list_of_args)
  end

  @spec start_link(module, (() -> term), options) :: on_start
  def start_link(module, fun, opts \\ [])
      when is_atom(module) and is_function(fun, 0) and is_list(opts) do
    do_start_link(module, [fun], opts)
  end

  @spec start_link(module, module, atom, args, options) :: on_start
  def start_link(module, mod, fun, args, opts \\ [])
      when is_atom(module) and is_atom(mod) and is_atom(fun) and is_list(args) and is_list(opts) do
    do_start_link(module, [mod, fun, args], opts)
  end

  @spec do_start_link(module, args, options) :: on_start
  defp do_start_link(module, args, opts) do
    attrs = get_start_attrs(module, args, opts)

    Agent.start_link(initialization_func(attrs), name: attrs.name)
    |> invoke_handle_start_callback(module, attrs)
  end

  @spec start_supervised(module, (() -> term), options) :: on_start_supervised
  def start_supervised(module, fun, opts \\ [])
      when is_atom(module) and is_function(fun, 0) and is_list(opts) do
    do_start_supervised(module, [fun], opts)
  end

  @spec start_supervised(module, module, atom, args, options) :: on_start_supervised
  def start_supervised(module, mod, fun, args, opts \\ [])
      when is_atom(module) and is_atom(mod) and is_atom(fun) and is_list(args) and is_list(opts) do
    do_start_supervised(module, [mod, fun, args], opts)
  end

  @spec do_start_supervised(module, args, options) :: on_start_supervised
  defp do_start_supervised(module, args, opts) do
    attrs = get_start_attrs(module, args, opts)
    child = {Receiver, [module, initialization_func(attrs), [name: attrs.name]]}

    DynamicSupervisor.start_child(Receiver.Sup, child)
    |> invoke_handle_start_callback(module, attrs)
  end

  @spec invoke_handle_start_callback(on_start | on_start_supervised, module, start_attrs) ::
          on_start | on_start_supervised
  defp invoke_handle_start_callback(on_start_result, module, attrs) do
    with {:ok, pid} <- on_start_result do
      apply(module, :handle_start, [attrs.receiver, pid, attrs.initial_state])
      {:ok, pid}
    end
  rescue
    # Catch `UndefinedFunctionError` raised from invoking the `handle_start/3` callback on a
    # module that hasn't defined it. At this point the receiver has already been started and
    # needs to be stopped gracefully so it isn't orphaned, then raise the exception.
    e in UndefinedFunctionError ->
      stop({module, attrs.receiver})
      raise e
  end

  @spec get_start_attrs(module, args, options) :: start_attrs
  defp get_start_attrs(module, args, opts) do
    task = apply(Task.Supervisor, :async, [Receiver.TaskSup | args])
    receiver = Keyword.get(opts, :as, :receiver)

    %{
      module: module,
      receiver: receiver,
      name: Keyword.get(opts, :name, registered_name(module, receiver)),
      initial_state: Task.await(task)
    }
  end

  @spec initialization_func(start_attrs) :: (() -> state)
  defp initialization_func(attrs) do
    # If an atom is provided as the `:name` option at `start*` it overrides the `:via` naming pattern,
    # skipping registration with the `Registry`. In this case the process needs to be manually registered
    # on initialization so the PID is associated with the receiver name and registered process name.
    # If the process has already been registered with the `:via` pattern then `Registry.register/3` returns
    # `{:error, {:already_registered, pid}}` and is effectively a noop. We do this from within the
    # initialization function because the calling process will be the one registered. See `Registry.register/3`.
    fn ->
      Registry.register(Receiver.Registry, {attrs.module, attrs.receiver}, attrs.name)
      attrs.initial_state
    end
  end

  @spec get(receiver) :: term
  def get(name), do: do_get(name, & &1)

  @spec get(receiver, (state -> term)) :: term
  def get(name, fun) when is_function(fun, 1), do: do_get(name, fun)

  defp do_get(name, fun) when (not is_nil(name) and is_atom(name)) or is_pid(name) do
    name
    |> validate_name()
    |> do_get(fun)
  end

  defp do_get({module, receiver} = name, fun) do
    state = Agent.get(whereis(name), fun)

    case apply(module, :handle_get, [receiver, state]) do
      {:reply, reply} -> reply
      :noreply -> state
    end
  end

  @spec update(receiver, (state -> state)) :: :ok
  def update(name, fun) when is_function(fun, 1), do: do_update(name, fun)

  defp do_update(name, fun) when (not is_nil(name) and is_atom(name)) or is_pid(name) do
    name
    |> validate_name()
    |> do_update(fun)
  end

  defp do_update({module, receiver} = name, fun) do
    {old_state, new_state} =
      Agent.get_and_update(whereis(name), fn old ->
        new = fun.(old)
        {{old, new}, new}
      end)

    apply(module, :handle_update, [receiver, old_state, new_state])
    :ok
  end

  @spec get_and_update(receiver, (state -> {term, state})) :: term
  def get_and_update(name, fun) when is_function(fun, 1), do: do_get_and_update(name, fun)

  defp do_get_and_update(name, fun) when (not is_nil(name) and is_atom(name)) or is_pid(name) do
    name
    |> validate_name()
    |> do_get_and_update(fun)
  end

  defp do_get_and_update({module, receiver} = name, fun) do
    {return_val, new_state} =
      Agent.get_and_update(whereis(name), fn old ->
        {return, new} = fun.(old)
        {{return, new}, new}
      end)

    case apply(module, :handle_get_and_update, [receiver, return_val, new_state]) do
      {:reply, reply} -> reply
      :noreply -> return_val
    end
  end

  @spec stop(receiver, reason :: term, timeout) :: :ok
  def stop(name, reason \\ :normal, timeout \\ :infinity), do: do_stop(name, reason, timeout)

  defp do_stop(name, reason, timeout) when (not is_nil(name) and is_atom(name)) or is_pid(name) do
    name
    |> validate_name()
    |> do_stop(reason, timeout)
  end

  defp do_stop({module, receiver} = name, reason, timeout) do
    pid = whereis(name)
    state = Agent.get(pid, & &1)

    with :ok <- Agent.stop(pid, reason, timeout) do
      apply(module, :handle_stop, [receiver, reason, state])
      :ok
    end
  end

  @spec validate_name(receiver) :: {module, atom}
  defp validate_name(name) do
    case which_receiver(name) do
      {_, _} = receiver ->
        receiver

      _ ->
        raise ArgumentError,
          message:
            "Expected an atom, pid, or two element tuple associated with a Receiver. Got #{
              IO.inspect(name)
            }"
    end
  end

  @doc """
  Returns the PID of a receiver process, or `nil` if it does not exist.

  Accepts one argument, either a two-element tuple containing the name of the
  callback module and an atom that is the name of the receiver, or a PID.
  """
  @spec whereis(receiver) :: pid | nil
  def whereis({mod, receiver} = name) when is_atom(mod) and is_atom(receiver) do
    case Registry.lookup(Receiver.Registry, name) do
      [{pid, _}] -> pid
      _ -> nil
    end
  end

  def whereis(pid) when is_pid(pid), do: pid

  def whereis(name) when is_atom(name), do: Process.whereis(name)

  @doc """
  Returns a two element tuple containing the callback module and name of the receiver associated
  with a PID or a registered process name.

  Accepts one argument, a PID or a `name`. `name` must be an atom that can be used to
  register a process with `Process.register/2`.
  """
  @spec which_receiver(receiver) :: {module, atom} | nil
  def which_receiver(pid) when is_pid(pid) do
    case Registry.keys(Receiver.Registry, pid) do
      [{_, _} = name] -> name
      [] -> nil
    end
  end

  def which_receiver(name) when is_atom(name) do
    with pid when is_pid(pid) <- Process.whereis(name), do: which_receiver(pid)
  end

  @doc """
  Returns the `name` of a registered process associated with a receiver. `name` must be an atom that
  can be used to register a process with `Process.register/2`.

  Accepts one argument, a PID or a two element tuple containing the callback module and the name of the
  receiver. Returns nil if no name was registered with the process.
  """
  @spec which_name(pid | receiver) :: atom | nil
  def which_name(pid) when is_pid(pid) do
    with receiver <- which_receiver(pid),
         [{^pid, name}] <- Registry.lookup(Receiver.Registry, receiver),
         do: name
  end

  def which_name({_, _} = receiver) do
    with [{_, name}] <- Registry.lookup(Receiver.Registry, receiver), do: name
  end

  @spec registered_name(module, receiver) :: registered_name
  defp registered_name(module, receiver) do
    {:via, Registry, {Receiver.Registry, {module, receiver}}}
  end

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      @behaviour Receiver

      {test, opts} = Keyword.pop(opts, :test, false)
      as = Keyword.get(opts, :as, :receiver)

      if test do
        defp unquote(:"start_#{as}")() do
          start_supervised({Receiver, [__MODULE__, fn -> [] end, unquote(opts)]})
        end

        defp unquote(:"start_#{as}")(fun) when is_function(fun, 0) do
          start_supervised({Receiver, [__MODULE__, fun, unquote(opts)]})
        end

        defp unquote(:"start_#{as}")(module, fun, args) do
          start_supervised({Receiver, [__MODULE__, module, fun, args, unquote(opts)]})
        end
      else
        defp unquote(:"start_#{as}")() do
          Receiver.start_supervised(__MODULE__, fn -> [] end, unquote(opts))
        end

        defp unquote(:"start_#{as}")(fun) when is_function(fun, 0) do
          Receiver.start_supervised(__MODULE__, fun, unquote(opts))
        end

        defp unquote(:"start_#{as}")(module, fun, args) do
          Receiver.start_supervised(__MODULE__, module, fun, args, unquote(opts))
        end
      end

      defp unquote(:"stop_#{as}")(reason \\ :normal, timeout \\ :infinity) do
        Receiver.stop({__MODULE__, unquote(as)}, reason, timeout)
      end

      defp unquote(:"get_#{as}")() do
        Receiver.get({__MODULE__, unquote(as)})
      end

      defp unquote(:"get_#{as}")(fun) when is_function(fun, 1) do
        Receiver.get({__MODULE__, unquote(as)}, fun)
      end

      defp unquote(:"update_#{as}")(fun) when is_function(fun, 1) do
        Receiver.update({__MODULE__, unquote(as)}, fun)
      end

      defp unquote(:"get_and_update_#{as}")(fun) when is_function(fun, 1) do
        Receiver.get_and_update({__MODULE__, unquote(as)}, fun)
      end

      defoverridable "start_#{as}": 0,
                     "start_#{as}": 1,
                     "start_#{as}": 3,
                     "stop_#{as}": 0,
                     "stop_#{as}": 1,
                     "stop_#{as}": 2,
                     "get_#{as}": 0,
                     "get_#{as}": 1,
                     "update_#{as}": 1,
                     "get_and_update_#{as}": 1

      @doc false
      def handle_stop(unquote(as), reason, state), do: :ok

      @doc false
      def handle_start(unquote(as), pid, state), do: :ok

      @doc false
      def handle_get(unquote(as), state), do: :noreply

      @doc false
      def handle_update(unquote(as), old_state, new_state), do: :ok

      @doc false
      def handle_get_and_update(unquote(as), return_val, new_state), do: :noreply

      defoverridable handle_stop: 3,
                     handle_start: 3,
                     handle_get: 2,
                     handle_update: 3,
                     handle_get_and_update: 3
    end
  end
end
