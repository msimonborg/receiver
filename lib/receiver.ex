defmodule Receiver do
  @moduledoc ~S"""
  Conveniences for creating processes that hold important state.

  A wrapper around an `Agent` that adds callbacks and reduces boilerplate code, making it
  quick and easy to store important state in a separate supervised process.

  # Use cases

    * Creating a "stash" to persist process state across restarts. See [example](#stash) below.

    * Application or server configuration. See [example](#config) below.

    * Storing mutable state outside of a worker process, or as a shared repository
    for multiple processes running the same module code. See [example](#a-look-at-callbacks) below.

    * Testing higher order functions. By passing a function call to a `Receiver` process into a higher
    order function you can test if the function is executed as intended by checking the change in state.
    See `ExUnitReceiver` module documentation.

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

  The line `use Receiver, as: :stash` creates an `Agent` named with the `:via` semantics of the `Registry` module.
  The stash is supervised in the `Receiver` application supervision tree, not in your own application's. It also
  defines the following *private* client functions in the `Counter` module:

    * `start_stash/0` - Defaults the inital state to an empty list.
    * `start_stash/1` - Expects an anonymous function that will return the initial state when called.
    * `start_stash/3` - Expects a module, function name, and list of args that will return the initial state
    when called.
    * `stop_stash/2` - Optional `reason` and `timeout` args. See `stop/3` for more information.
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

      # Stop the counter, initiating a restart and losing the counter state
      GenServer.stop(Counter)
      #=> :ok

      # Get the counter state, which was persisted across restarts with help of the stash
      Counter.get()
      #=> 2

  ## <a name="client-functions"></a>Client functions

  When we `use Receiver, as: :stash` above, the following private function definitions
  are automatically generated inside the `Counter` module:

      defp start_stash do
        Receiver.start_supervised({__MODULE__, :stash}, fn -> [] end)
      end

      defp start_stash(fun) do
        Receiver.start_supervised({__MODULE__, :stash}, fun)
      end

      defp start_stash(module, fun, args)
        Receiver.start_supervised({__MODULE__, :stash}, module, fun, args)
      end

      defp stop_stash(reason \\ :normal, timeout \\ :infinity) do
        Receiver.stop({__MODULE__, :stash}, reason, timeout)
      end

      defp get_stash do
        Receiver.get({__MODULE__, :stash})
      end

      defp get_stash(fun) do
        Receiver.get({__MODULE__, :stash}, fun)
      end

      defp update_stash(fun) do
        Receiver.update({__MODULE__, :stash}, fun)
      end

      defp get_and_update_stash(fun) do
        Receiver.get_and_update({__MODULE__, :stash}, fun)
      end

  These are private to encourage starting, stopping, and updating the stash from only the `Counter` API.
  A receiver can always be manipulated by calling the `Receiver` functions directly
  i.e. `Receiver.update({Counter, :stash}, & &1 + 1)`, but use these functions with caution to avoid
  race conditions.

  ## <a name="config"></a>Using as a configuration store

  A `Receiver` can be used to store application configuration, and even be initialized
  at startup. Since the receiver processes are supervised in a separate application
  that is started as a dependency of yours, it will already be ready to start even before your
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

  ## <a name="a-look-at-callbacks"></a>A look at callbacks

  The first argument to all of the callbacks is the name of the receiver. This will either be the atom passed to
  the `:as` option or the default name `:receiver`. The intent is to avoid any naming collisions with other `handle_*`
  callbacks.

      defmodule Account do
        use GenServer
        use Receiver, as: :ledger

        # Client API
        def start_link(initial_balance) do
          start_ledger(fn -> %{} end)
          GenServer.start_link(__MODULE__, initial_balance)
        end

        def get_balance_history(pid) do
          get_ledger(fn ledger -> Map.get(ledger, pid) end)
        end

        def transact(pid, amount) do
          GenServer.cast(pid, {:transact, amount})
        end

        # GenServer callbacks

        def init(initial_balance) do
          pid = self()
          update_ledger(fn ledger -> Map.put(ledger, pid, [initial_balance]) end)
          {:ok, initial_balance}
        end

        def handle_cast({:transact, amount}, balance) do
          pid = self()
          new_balance = balance + amount
          update_ledger(fn ledger -> Map.update(ledger, pid, [new_balance], &([new_balance | &1])) end)
          {:noreply, new_balance}
        end

        # Receiver callbacks

        def handle_start(:ledger, pid, _state) do
          IO.inspect(pid, label: "Started ledger")
          IO.inspect(self(), label: "From caller")
        end

        def handle_get(:ledger, history) do
          current_balance = history |> List.first()
          IO.inspect(self(), label: "Handling get from")
          IO.inspect(current_balance, label: "Current balance")
          :noreply
        end

        def handle_update(:ledger, _old_state, new_state) do
          pid = self()
          new_balance = new_state |> Map.get(pid) |> List.first()
          IO.inspect(pid, label: "Handling update from")
          IO.inspect(new_balance, label: "Balance updated to")
        end
      end

  All of the callbacks are invoked within the calling process, not the receiver process.

      {:ok, one} = Account.start_link(10.0)
      # Started ledger: #PID<0.213.0>
      # From caller: #PID<0.206.0>
      # Handling update from: #PID<0.214.0>
      # Balance updated to: 10.0
      #=> {:ok, #PID<0.214.0>}

      Process.whereis(Receiver.Sup)
      #=> #PID<0.206.0>
      Receiver.whereis({Account, :ledger})
      #=> #PID<0.213.0>
      self()
      #=> #PID<0.210.0>

  In `Account.start_link/1` a ledger is started with a call to `start_ledger/1`. `#PID<0.213.0>` is the ledger pid,
  and the calling process `#PID<0.206.0>` handles the `handle_start/3` callback as can be seen in the output.
  The calling process in this case is `Receiver.Sup`, the `DynamicSupervisor` that supervises all receivers
  when started with the private convenience functions and is the process that makes the actual call to
  `Receiver.start_link/1`.

  When `init/1` is invoked in the account server (`#PID<0.214.0>`) it updates the ledger with it's starting balance by
  making a call to `update_ledger/1`, and receives the `handle_update/3` callback.

      {:ok, two} = Account.start_link(15.0)
      # Handling update from: #PID<0.219.0>
      # Balance updated to: 15.0
      #=> {:ok, #PID<0.219.0>}

  When `start_link/1` is called the second time the ledger already exists so the call to `start_ledger/1` is
  a noop and the `handle_start/3` callback is never invoked.

      Account.get_balance_history(one)
      # Handling get from: #PID<0.210.0>
      # Current balance: 10.0
      #=> [10.0]

      Account.get_balance_history(two)
      # Handling get from: #PID<0.210.0>
      # Current balance: 15.0
      #=> [15.0]

      Account.transact(one, 15.0)
      # Handling update from: #PID<0.214.0>
      # Balance updated to: 25.0
      #=> :ok

  This may be confusing at first, and it's different from the way callbacks are dispatched in a GenServer for
  example. The important thing to remember is that the receiver does not invoke the callbacks, they are always
  invoked from the process that's sending it the message.

  A `Receiver` is meant to be isolated from complex and potentially error-prone operations. It only exists to
  hold important state and should be protected from failure and remain highly available. The callbacks provide
  an opportunity to perform additional operations with the receiver data, such as interacting with the outside
  world, that may have no impact on the return value and do not expose the receiver itself to errors or block
  the process from answering other callers. The goal is to keep the functions passed to the receiver as simple
  as possible and perform more complex operations in the callbacks.
  """

  use Agent, restart: :transient

  @typedoc "The receiver name"
  @type receiver :: atom | {module, atom} | pid

  @typedoc "Return values of `start_supervised/3` and `start_supervised/5`"
  @type on_start_supervised :: DynamicSupervisor.on_start_child() | start_error

  @typedoc "Return values of `start/3` and `start/5`"
  @type on_start :: Agent.on_start() | start_error

  @typedoc "Error tuple returned for pattern matching on function results"
  @type start_error ::
          {:error, {%UndefinedFunctionError{} | %FunctionClauseError{}, stacktrace :: list}}

  @typedoc "Error returned from bad arguments"
  @type not_found_error :: {:error, {%Receiver.NotFoundError{}, stacktrace :: list}}

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
  Invoked in the calling process after the receiver is started. All `start*` functions will block until it returns.

  `atom` is the name of the receiver passed to the `:as` option at start. Defaults to `:receiver`.

  `pid` is the PID of the receiver process, `state` is the starting state of the receiver after the initializing
  function is called.

  If the receiver was already started when `start*` was called then the callback will not be invoked.

  The return value is ignored.
  """
  @callback handle_start(atom, pid, state) :: term

  @doc """
  Invoked in the calling process after the receiver is stopped. `stop/3` will block until it returns.

  `atom` is the name of the receiver passed to the `:as` option at start. Defaults to `:receiver`.

  `reason` is the exit reason, `state` is the receiver state at the time of shutdown. See `Agent.stop/3`
  for more information.

  The return value is ignored.
  """
  @callback handle_stop(atom, reason :: term, state) :: term

  @doc """
  Invoked in the calling process after a `get` request is sent to the receiver. `get/1` and `get/2`
  will block until it returns.

  `atom` is the name of the receiver passed to the `:as` option at start. Defaults to `:receiver`.

  `return_value` is the return value of the `get*` anonymous function. With a basic `get` function this is
  often the current state of the receiver.

  Returning `{:reply, reply}` causes `reply` to be the return value of `get/1` and `get/2`
  (and the private `get_receiver` client functions).

  Returning `:noreply` defaults the return value of `get*` to the `state`.
  This can be useful if action needs to be performed with the `state` value but there's no desire
  to modify the return value of the calling function.
  """
  @callback handle_get(atom, return_value :: term) :: {:reply, reply :: term} | :noreply

  @doc """
  Invoked in the calling process after an `update` is sent to the receiver. `update/2` will
  block until it returns.

  `atom` is the name of the receiver passed to the `:as` option at start. Defaults to `:receiver`.

  `old_state` is the state of the receiver before `update/2` was called. `state` is the updated
  state of the receiver.

  The return value is ignored.
  """
  @callback handle_update(atom, old_state :: state, state) :: term

  @doc """
  Invoked in the calling process after a `get_and_update` is sent to the receiver. `get_and_update/2` will
  block until it returns.

  `atom` is the name of the receiver passed to the `:as` option at start. Defaults to `:receiver`.

  `return_val` is the first element of the tuple (the return value) of the anonymous function passed to
  `get_and_update/2`.

  `state` is the second element of the tuple and is the new state of the receiver.

  Returning `{:reply, reply}` causes `reply` to be the return value of `get_and_update/2`
  (and the private `get_and_update_receiver` client function).

  Returning `:noreply` defaults the return value of `get_and_update/2` to `return_val`.
  """
  @callback handle_get_and_update(atom, return_value :: term, state) ::
              {:reply, reply :: term} | :noreply

  @optional_callbacks handle_start: 3,
                      handle_stop: 3,
                      handle_get: 2,
                      handle_update: 3,
                      handle_get_and_update: 3

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

  Only use this is if you want to supervise your own receiver from application startup. In most cases you can
  simply use the `start_supervised*` functions to start a supervised receiver dynamically in an isolated
  application. See `start_supervised/3` and `start_supervised/5` for more information.
  """
  @spec start_link(start_args) :: on_start
  def start_link(list_of_args) when is_list(list_of_args) do
    apply(__MODULE__, :start_link, list_of_args)
  end

  @spec start_link(module, (() -> term), options) :: on_start
  def start_link(module, fun, opts \\ [])
      when is_atom(module) and is_function(fun, 0) and is_list(opts) do
    do_start(:link, module, [fun], opts)
  end

  @spec start_link(module, module, atom, args, options) :: on_start
  def start_link(module, mod, fun, args, opts \\ [])
      when is_atom(module) and is_atom(mod) and is_atom(fun) and is_list(args) and is_list(opts) do
    do_start(:link, module, [mod, fun, args], opts)
  end

  @doc """
  Starts a new receiver without links (outside of a supervision tree).

  See `start_link/3` for more information.
  """
  @spec start(module, (() -> term), options) :: on_start
  def start(module, fun, opts \\ [])
      when is_atom(module) and is_function(fun, 0) and is_list(opts) do
    do_start(:nolink, module, [fun], opts)
  end

  @spec start(module, module, atom, args, options) :: on_start
  def start(module, mod, fun, args, opts \\ [])
      when is_atom(module) and is_atom(mod) and is_atom(fun) and is_list(args) and is_list(opts) do
    do_start(:nolink, module, [mod, fun, args], opts)
  end

  @spec do_start(:link | :nolink, module, args, options) :: on_start
  defp do_start(link, module, args, opts) do
    attrs = get_start_attrs(module, args, opts)

    start_function =
      case link do
        :link -> :start_link
        :nolink -> :start
      end

    Agent
    |> apply(start_function, [initialization_func(attrs), [name: attrs.name]])
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
    child = {Receiver, [module | args] ++ [opts]}

    DynamicSupervisor.start_child(Receiver.Sup, child)
  end

  @spec invoke_handle_start_callback(
          Agent.on_start() | DynamicSupervisor.on_start_child(),
          module,
          start_attrs
        ) ::
          on_start | on_start_supervised
  defp invoke_handle_start_callback(on_start_result, module, attrs) do
    with {:ok, pid} <- on_start_result do
      apply(module, :handle_start, [attrs.receiver, pid, attrs.initial_state])
      {:ok, pid}
    end
  rescue
    # Catch `UndefinedFunctionError` (raised from invoking the `handle_start/3` callback on a
    # module that hasn't defined it) and `FunctionClauseError` (raised from a bad pattern match,
    # due to an invalid receiver name passed with the `:as` options). At this point the receiver
    # has already been started and needs to be stopped gracefully so it isn't orphaned, then return
    # the error tuple.
    exception in [UndefinedFunctionError, FunctionClauseError] ->
      Agent.stop(attrs.name)
      {:error, {exception, __STACKTRACE__}}
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
  def get(name), do: get(name, & &1)

  @spec get(receiver, (state -> term)) :: term
  def get(name, fun)
      when is_function(fun, 1) and
             ((not is_nil(name) and is_atom(name)) or is_pid(name) or is_tuple(name)) do
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
  def update(name, fun)
      when is_function(fun, 1) and
             ((not is_nil(name) and is_atom(name)) or is_pid(name) or is_tuple(name)) do
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
  def get_and_update(name, fun)
      when is_function(fun, 1) and
             ((not is_nil(name) and is_atom(name)) or is_pid(name) or is_tuple(name)) do
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
  def stop(name, reason \\ :normal, timeout \\ :infinity)
      when (not is_nil(name) and is_atom(name)) or is_pid(name) or
             is_tuple(name) do
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

  @spec validate_name(receiver) :: {module, atom} | not_found_error
  defp validate_name(name) do
    case which_receiver(name) do
      {_, _} = tuple ->
        tuple

      _ ->
        name = with {mod, atom} <- name, do: "{#{inspect(mod)}, #{inspect(atom)}}"

        stacktrace =
          self()
          |> Process.info(:current_stacktrace)
          |> elem(1)
          |> List.delete_at(0)
          |> List.delete_at(0)

        exception = %Receiver.NotFoundError{
          message: """
            Expected input to be one of the following terms associate with a Receiver:

                * atom - the global process name
                * pid - the identifier of the process
                * {module, atom} - the callback module and receiver name

            No Receiver is associated with the input: #{inspect(name)}
          """
        }

        reraise exception, stacktrace
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

  def which_receiver({_, _} = tuple) do
    case Registry.lookup(Receiver.Registry, tuple) do
      [{pid, name}] when is_pid(pid) and is_atom(name) -> tuple
      _ -> nil
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

        defp unquote(:"start_#{as}")(fun) do
          start_supervised({Receiver, [__MODULE__, fun, unquote(opts)]})
        end

        defp unquote(:"start_#{as}")(module, fun, args) do
          start_supervised({Receiver, [__MODULE__, module, fun, args, unquote(opts)]})
        end
      else
        defp unquote(:"start_#{as}")() do
          Receiver.start_supervised(__MODULE__, fn -> [] end, unquote(opts))
        end

        defp unquote(:"start_#{as}")(fun) do
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

      defp unquote(:"get_#{as}")(fun) do
        Receiver.get({__MODULE__, unquote(as)}, fun)
      end

      defp unquote(:"update_#{as}")(fun) do
        Receiver.update({__MODULE__, unquote(as)}, fun)
      end

      defp unquote(:"get_and_update_#{as}")(fun) do
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
