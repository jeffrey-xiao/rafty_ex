defmodule Rafty.Server.Supervisor do
  use Supervisor

  def start_link({server_name, _node_name, _cluster_config} = args) do
    Supervisor.start_link(__MODULE__, args, name: server_supervisor_name(server_name))
  end

  def server_supervisor_name(server_name) do
    :"ServerSupervisor#{server_name}"
  end

  def init(args) do
    children = [
      {Rafty.Server, args}
      # TODO: Add log GenServer
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
