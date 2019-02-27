defmodule ExUnit.Receiver.Example.CounterTest do
  use ExUnit.Case
  alias Receiver.Example.Counter

  setup do
    start_supervised({Counter, 0})
    on_exit(fn -> Counter.stop_stash end)
  end

  test "it initializes the stash with it's default value" do
    assert Counter.get == 0
    assert Counter.get_stash == 0
  end

  test "it changes its state without changing the state of the stash" do
    assert Counter.get == 0
    Counter.increment(4)
    assert Counter.get == 4
    assert Counter.get_stash == 0
  end

  test "it sends its state to the stash on exit, and recovers it on restart" do
    Counter.increment(4)
    assert Counter.get == 4
    assert Counter.get_stash == 0

    GenServer.stop(Counter)
    Counter.start_link([])

    assert Counter.get == 4
    assert Counter.get_stash == 4
  end
end
