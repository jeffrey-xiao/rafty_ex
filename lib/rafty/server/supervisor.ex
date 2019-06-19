defmodule Rafty.Server.Supervisor do
  @moduledoc """
  Supervisor for a server. It starts a `Rafty.Log.Server`, `Rafty.FSM.Server`, and a `Rafty.Server`.
  """

  use Supervisor

  @doc """
  Starts a `Rafty.Server.Supervisor` process linked to the current process.
  """
  @spec start_link(Rafty.args()) :: Supervisor.on_start()
  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: name(args[:server_name]))
  end

  @doc """
  Returns the name of the supervisor.
  """
  @spec name(Rafty.server_name()) :: atom()
  def name(server_name) do
    :"ServerSupervisor#{server_name}"
  end

  @impl Supervisor
  def init(args) do
    children = [
      {Rafty.Log.Server, args},
      {Rafty.FSM.Server, args},
      {Rafty.Server, args}
    ]

    opts = [strategy: :one_for_one]
    Supervisor.init(children, opts)
  end
end
