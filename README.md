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

A simple wrapper around an `Agent` that reduces boilerplate code and makes it easy to store
state in a separate supervised process.

# Use cases

  * Creating a "stash" to persist process state across restarts. See [example](#example) below.

  * Storing persistent process state outside of the worker process, or as a shared repository
  for multiple processes.

  * Testing higher order functions. By passing a function call to a `Receiver` process into a higher
  order function you can test if the function is executed as intended by checking the change in state.

### [See documentation](https://hexdocs.pm/receiver/Receiver.html) for other usage and complete API reference.

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
# Stop the counter, initiating a restart
GenServer.stop(Counter)
#=> :ok
# Get the counter state, which was persisted across restarts
Counter.get()
#=> 2
```

# Contributing
Clone this repository and run the tests with `mix test` to make sure they pass. Make your changes, writing tests for all new functionality. Changes will not be merged without accompanying tests. Run `mix test` again to make sure all tests are passing, and run `mix format` to format the code, too. Now you're ready to submit a [pull request](https://help.github.com/en/articles/about-pull-requests)

# License
MIT