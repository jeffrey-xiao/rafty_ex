defmodule Rafty.Log.Server do
  use GenServer

  defstruct [
    :log,
    :log_state
  ]

  def start_link({server_name, _log_module} = args) do
    GenServer.start_link(__MODULE__, args, name: name(server_name))
  end

  def name(server_name) do
    :"LogServer_#{server_name}"
  end

  @impl GenServer
  def init({server_name, log_module} = args) do
    {:ok, %__MODULE__{log: log_module, log_state: log_module.init(server_name)}}
  end
end
