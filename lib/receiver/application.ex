defmodule Receiver.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Receiver.Sup},
      {Registry, keys: :unique, name: Receiver.Registry},
      {Task.Supervisor, name: Receiver.TaskSup}
    ]

    opts = [strategy: :one_for_one, name: Receiver.App]
    Supervisor.start_link(children, opts)
  end
end
