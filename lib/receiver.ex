defmodule Receiver do
  @moduledoc """
  Conveniences for creating processes that hold state.

  A simple wrapper around an `Agent` that reduces boilerplate code and makes it easy to store
  state in a separate supervised process.

  # Use cases

    * Storing persistent process state outside of the worker process, or as a shared repository
    for multiple processes.

    * Creating a "stash" to persist process state across restarts. See example below.

    * Testing higher order functions. By passing a function call to a `Receiver` process into a higher
    order function you can test if the function is executed as intended by checking the change in state.

  ## Example

      defmodule Counter do
        @moduledoc false
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
        # started its state will not change. The state of the stash is returned as the
        # initial counter state whenever the counter is started.
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
        # it restarts.
        def terminate(_reason, state) do
          update_stash(fn _ -> state end)
        end
      end

  The line `use Receiver, as: :stash` creates a module and named `Agent` process with the name `Counter.Stash`.
  The stash is supervised in the `Receiver` application supervision tree, not in your own application's. It also
  defines the following client functions in the `Counter` module:

    * `start_stash/0` - Defaults the inital state to an empty list.
    * `start_stash/1` - Expects a value or anonymous function that will return the initial state.
    * `start_stash/3` - Expects a module, function name, and list of args that will return the initial state
    when called.
    * `stop_stash/2` - Optional `reason` and `timeout` args. See `Agent.stop/3` for more information.
    * `get_stash/0` - Returns the current state of the stash.
    * `update_stash/1` - Updates the state of the stash. expects a value or an anonymous function that receives
    the current state as an argument and returns the updated state.

  If no `:as` option were given in this example then the process would take the name `Counter.Receiver`, and the
  functions would be named like `start_receiver/0`.

  The `Counter` can now be supervised and its state will be isolated from failure and persisted across restarts.

      # Start the counter under a supervisor
      {:ok, _pid} = Supervisor.start_link([{Counter, }], strategy: :one_for_one)

      # Get the state of the counter
      Counter.get()
      #=> 0

      # Increment the counter
      Counter.increment(2)
      #=> :ok

      # Get the updated state of the counter
      Counter.get()
      #=> 2

      # The stash is still set to the initial value
      Counter.get_stash()
      #=> 0

      # Stop the counter, initiating a restart
      GenServer.stop(Counter)
      #=> :ok

      # Get the counter state, which was persisted across restarts
      Counter.get()
      #=> 2

      # Get the state of the stash, which was updated when the counter exited
      Counter.get_stash()
      #=> 2
  """

  @type receiver :: :receiver | atom
  @type state :: term
  @type old_state :: state
  @type reason :: term
  @type mod :: term
  @type on_start :: DynamicSupervisor.on_start_child()
  @type args :: [term]
  @type on_get :: {:reply, any} | :noreply

  @callback handle_start(receiver, pid, state) :: term

  @callback handle_stop(receiver, reason, state) :: term

  @callback handle_get(receiver, state) :: on_get

  @callback handle_update(receiver, old_state, state) :: term

  defp receiver_module_name(receiver, namespace) when is_atom(receiver) do
    namespace
    |> Module.split()
    |> Enum.concat([Atom.to_string(receiver) |> Macro.camelize()])
    |> Module.concat()
  end

  @spec start(module, receiver, fun) :: on_start
  def start(module, receiver \\ :receiver, fun) when is_function(fun) do
    do_start(module, receiver, fun)
  end

  @spec start(module, receiver, mod, fun, args) :: on_start
  def start(module, receiver \\ :receiver, mod, fun, args) do
    do_start(module, receiver, [mod, fun, args])
  end

  defp do_start(module, receiver, arg) do
    child = {receiver_module_name(receiver, module), arg}
    case DynamicSupervisor.start_child(Receiver.Supervisor, child) do
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
    state = Agent.get(receiver_module_name(receiver, module), fun)
    case apply(module, :handle_get, [receiver, state]) do
      {:reply, result} -> result
      :noreply -> state
    end
  end

  @spec update(module, receiver, fun(any)) :: :ok
  def update(module, receiver \\ :receiver, fun) do
    old_state = Agent.get(receiver_module_name(receiver, module), & &1)
    Agent.update(receiver_module_name(receiver, module), fun)
    new_state = Agent.get(receiver_module_name(receiver, module), & &1)
    apply(module, :handle_update, [receiver, old_state, new_state])
    :ok
  end

  def stop(module, receiver \\ :receiver, reason \\ :normal, timeout \\ :infinity) do
    state = Agent.get(receiver_module_name(receiver, module), & &1)
    res = Agent.stop(receiver_module_name(receiver, module), reason, timeout)
    apply(module, :handle_stop, [receiver, reason, state])
    res
  end

  defmacro __using__(opts) do
    {name, opts} = Keyword.pop(opts, :as, :receiver)
    {test, _} = Keyword.pop(opts, :test, false)

    module_name = receiver_module_name(name, __CALLER__.module)

    quote bind_quoted: [name: name, module_name: module_name, test: test] do
      import Receiver

      @receiver_module_name module_name

      @behaviour Receiver

      defmodule module_name do
        @moduledoc false
        use Agent, restart: :transient

        def start_link(arg)

        def start_link([module, fun, args]) do
          Agent.start_link(module, fun, args, name: __MODULE__)
        end

        def start_link(fun) when is_function(fun) do
          Agent.start_link(fun, name: __MODULE__)
        end
      end

      if test do
        def unquote(:"start_#{name}")(fun) when is_function(fun) do
          start_supervised({@receiver_module_name, fun})
        end

        def unquote(:"start_#{name}")(module, fun, args) do
          start_supervised({@receiver_module_name, [module, fun, args]})
        end
      else
        def unquote(:"start_#{name}")(fun) when is_function(fun) do
          Receiver.start(__MODULE__, unquote(name), fun)
        end

        def unquote(:"start_#{name}")(module, fun, args) do
          Receiver.start(__MODULE__, unquote(name), module, fun, args)
        end
      end

      def unquote(:"stop_#{name}")(reason \\ :normal, timeout \\ :infinity) do
        Receiver.stop(__MODULE__, unquote(name), reason, timeout)
      end

      def unquote(:"get_#{name}")() do
        Receiver.get(__MODULE__, unquote(name))
      end

      def unquote(:"update_#{name}")(fun) when is_function(fun) do
        Receiver.update(__MODULE__, unquote(name), fun)
      end

      def unquote(:"update_#{name}")(value) do
        Receiver.update(__MODULE__, unquote(name), fn _ -> value end)
      end

      def handle_stop(unquote(name), reason, state), do: :ok

      def handle_start(unquote(name), pid, state), do: :ok

      def handle_get(unquote(name), state), do: :noreply

      def handle_update(unquote(name), old_state, new_state), do: :ok
    end
  end
end
