defmodule ExUnit.CounterTest do
  use ExUnit.Case

  setup do
    start_supervised({Counter, 0})
    on_exit(fn -> Receiver.stop({Counter, :stash}) end)
  end

  test "it initializes the stash with it's default value" do
    assert Counter.get == 0
    assert Receiver.get({Counter, :stash}) == 0
  end

  test "it changes its state without changing the state of the stash" do
    assert Counter.get == 0
    Counter.increment(4)
    assert Counter.get == 4
    assert Receiver.get({Counter, :stash}) == 0
  end

  test "it sends its state to the stash on exit, and recovers it on restart" do
    Counter.increment(4)
    assert Counter.get == 4
    assert Receiver.get({Counter, :stash}) == 0

    GenServer.stop(Counter)
    Counter.start_link([])

    assert Counter.get == 4
    assert Receiver.get({Counter, :stash}) == 4
  end
end
