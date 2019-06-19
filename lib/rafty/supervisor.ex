defmodule Rafty.Supervisor do
  @moduledoc """
  Supervisor for the Rafty application. It starts `Rafty.RPC.Supervisor` and
  `Rafty.ServersSupervisor`.
  """

  use Supervisor

  @moduledoc """
  Starts a `Rafty.Supervisor` process linked to the current process.
  """
  @spec start_link :: Supervisor.on_start()
  def start_link do
    Supervisor.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl Supervisor
  def init(_args) do
    children = [
      {Task.Supervisor, name: Rafty.RPC.Supervisor},
      Rafty.ServersSupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
