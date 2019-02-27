defmodule Receiver.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Receiver.Supervisor}
    ]

    opts = [strategy: :one_for_one, name: Receiver]
    Supervisor.start_link(children, opts)
  end
end
