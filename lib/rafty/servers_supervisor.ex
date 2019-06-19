defmodule Rafty.ServersSupervisor do
  @moduledoc """
  Dynamic supervisor that supervises `Rafty.Server.Supervisor`.
  """

  use DynamicSupervisor

  @moduledoc """
  Starts a `Rafty.ServersSupervisor` process linked to the current process.
  """
  @spec start_link(Rafty.args()) :: Supervisor.on_start()
  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Starts a new server on the current node with the specified arguments.
  """
  @spec start_server(Rafty.args()) :: DynamicSupervisor.on_start_child()
  def start_server(args) do
    child_spec = {Rafty.Server.Supervisor, Map.put(args, :node_name, node())}

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Terminates a server with the specified id.
  """
  @spec terminate_server(Rafty.id()) :: :ok | {:error, :not_found}
  def terminate_server(id) do
    {server_name, _node_name} = id

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
