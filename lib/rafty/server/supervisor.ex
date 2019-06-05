defmodule Rafty.Server.Supervisor do
  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: name(args[:server_name]))
  end

  def name(server_name) do
    :"ServerSupervisor#{server_name}"
  end

  @impl Supervisor
  def init(args) do
    children = [
      {Rafty.Log.Server, args},
      {Rafty.Server, args}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
