defmodule Rafty.ServersSupervisor do
  use DynamicSupervisor

  @spec start_link(Rafty.args()) :: DynamicSupervisor.on_start()
  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec start_server(Rafty.args()) :: DynamicSupervisor.on_start_child()
  def start_server(args) do
    child_spec = {Rafty.Server.Supervisor, Map.put(args, :node_name, node())}

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @spec terminate_server(Rafty.server_name()) :: :ok | {:error, :not_found}
  def terminate_server(server_name) do
    DynamicSupervisor.terminate_child(
      __MODULE__,
      Process.whereis(Rafty.Server.Supervisor.name(server_name))
    )
  end

  @impl DynamicSupervisor
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
