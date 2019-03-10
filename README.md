# Receiver

[![Build Status](https://travis-ci.org/msimonborg/receiver.svg?branch=master)](https://travis-ci.org/msimonborg/receiver)
[![Coverage Status](https://coveralls.io/repos/github/msimonborg/receiver/badge.svg?branch=master)](https://coveralls.io/github/msimonborg/receiver?branch=master)
[![Hex pm](https://img.shields.io/hexpm/v/receiver.svg?style=flat)](https://hex.pm/packages/receiver)

Conveniences for creating processes that hold important state.

A wrapper around an `Agent` that adds callbacks and reduces boilerplate code, making it
quick and easy to store important state in a separate supervised process.

# Use cases

  * Creating a "stash" to persist process state across restarts. See [example](#stash) below.

  * Application or server configuration. See [example](#config) below.

  * Storing persistent process state outside of the worker process, or as a shared repository
  for multiple processes.

  * Testing higher order functions. By passing a function call to a `Receiver` process into a higher
  order function you can test if the function is executed as intended by checking the change in state.
  See [ExUnitReceiver](#exunitreceiver) below.

### [See documentation](https://hexdocs.pm/receiver/Receiver.html) for other usage and complete API reference.

## Installation

```elixir
def deps do
  [
    {:receiver, "~> 0.1.0"}
  ]
end
```

# Examples

## Stash

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
# Stop the counter, initiating a restart and losing the counter state
GenServer.stop(Counter)
#=> :ok
# Get the counter state, which was persisted across restarts with help of the stash
Counter.get()
#=> 2
```

## Config
A `Receiver` can be used to store application configuration, and even be initialized
at startup. Since the receiver processes are supervised in a separate application
that is started as a dependency of yours, it will already be ready to start even before your
application's `start/2` callback has returned:

```elixir
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
```
Now the configuration can be globally read with the public `MyApp.config/0`.

```elixir
MyApp.config()
#=> %{setup: :default}

MyApp.config.setup
#=> :default
```

# ExUnitReceiver
A `Receiver` can be used to test higher order functions by using `ExUnitReceiver` in an `ExUnit` test case.
Consider the following example:

```elixir
defmodule Worker do
  def perform_complex_work(val, fun) do
    val
    |> do_some_work()
    |> fun.()
    |> do_other_work()
  end

  def do_some_work(val), do: val |> :math.log() |> round()

  def do_other_work(val), do: val |> :math.exp() |> round()
end

defmodule ExUnit.HigherOrderTest do
  use ExUnit.Case
  use ExUnitProperties
  use ExUnitReceiver

  setup do
    start_receiver(fn -> nil end)
    :ok
  end

  def register(x) do
    get_and_update_receiver(fn _ -> {x, x} end)
  end

  property "it does the work in stages with help from an anonymous function" do
    check all int <- positive_integer() do
      result = Worker.perform_complex_work(int, fn x -> register(x) end)
      receiver = get_receiver()

      assert Worker.do_some_work(int) == receiver
      assert Worker.do_other_work(receiver) == result
    end
  end
end
```

When you call the `start_receiver` functions within a `setup` block, it delegates to
`ExUnit.Callbacks.start_supervised/2`. This will start the receiver as a supervised process under
the test supervisor, automatically starting and shutting it down between tests to clean up state.
This can help you test that your higher order functions are executing with the correct arguments
and returning the expected results.

# Contributing
Clone this repository and run the tests with `mix test` to make sure they pass. Make your changes, writing tests for all new functionality. Changes will not be merged without accompanying tests. Run `mix test` again to make sure all tests are passing, and run `mix format` to format the code, too. Now you're ready to submit a [pull request](https://help.github.com/en/articles/about-pull-requests)

# License
[MIT - Copyright (c) 2019 M. Simon Borg](LICENSE.txt)