defmodule Receiver.Supervisor do
  use DynamicSupervisor

  @name __MODULE__

  def start_link([]) do
    DynamicSupervisor.start_link(@name, :ok, name: @name)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
