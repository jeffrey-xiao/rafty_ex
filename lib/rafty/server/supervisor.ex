defmodule Rafty.Server.Supervisor do
  use Supervisor

  def start_link({server_name, _node_name, _cluster_config, _fsm, _log} = args) do
    Supervisor.start_link(__MODULE__, args, name: name(server_name))
  end

  def name(server_name) do
    :"ServerSupervisor#{server_name}"
  end

  @impl Supervisor
  def init({server_name, _node_name, _cluster_config, _fsm, log} = args) do
    children = [
      {Rafty.Log.Server, {server_name, log}},
      {Rafty.Server, args}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
