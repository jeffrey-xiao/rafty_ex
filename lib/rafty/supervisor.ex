defmodule Rafty.Supervisor do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def init(_args) do
    children = [
      {Task.Supervisor, name: Rafty.RPC.Supervisor},
      Rafty.ServersSupervisor
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end
end
