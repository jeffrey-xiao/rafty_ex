defmodule Rafty.Server do
  use GenServer
  alias Rafty.Server.State

  def start_link({server_name, node_name} = args) do
    GenServer.start_link(__MODULE__, args, name: server_name(server_name))
  end

  def server_name(server_name) do
    :"Server#{server_name}"
  end

  def init({server_name, node_name} = args) do
    {:ok, %State{}}
  end
end
