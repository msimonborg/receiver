defmodule Receiver.Example.Counter do
  use GenServer
  use Receiver, as: :stash

  @name __MODULE__

  def start_link(arg) do
    GenServer.start_link(@name, arg, name: @name)
  end

  def increment(num) do
    GenServer.cast(@name, {:increment, num})
  end

  def get do
    GenServer.call(@name, :get)
  end

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

  def terminate(_reason, state) do
    update_stash(state)
  end
end
