defmodule Receiver.Server do
  @moduledoc false
  use Agent, restart: :transient

  def start_link([fun, name: name]) when is_function(fun) do
    Agent.start_link(fun, name: name)
  end

  def start_link([module, function, args, name: name]) do
    Agent.start_link(module, function, args, name: name)
  end
end
