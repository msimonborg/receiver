# Receiver

Conveniences for creating simple processes that hold state.

## Installation

```elixir
def deps do
  [
    {:receiver, "~> 0.1.0"}
  ]
end
```
[Documentation](https://hexdocs.pm/receiver).

A simple wrapper around an `Agent` that reduces boilerplate code and makes it easy to store
  state in a separate supervised process.

  # Use cases

    * Storing persistent process state outside of the worker process, or as a shared repository
    for multiple processes.

    * Creating a "stash" to persist process state across restarts. See example below.

    * Testing higher order functions. By passing a function call to a `Receiver` process into a higher
    order function you can test if the function is executed as intended by checking the change in state.

  ## Example

  ```elixir
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
      start_stash(arg)
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
      update_stash(state)
    end
  end
  ```

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

  ```elixir
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
  ```