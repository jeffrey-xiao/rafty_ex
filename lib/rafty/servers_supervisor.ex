defmodule Rafty.ServersSupervisor do
  use DynamicSupervisor

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def start_server(server_name, cluster_config) do
    child_spec = {Rafty.Server.Supervisor, {server_name, node(), cluster_config}}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
