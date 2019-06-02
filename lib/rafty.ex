defmodule Rafty do
  use Application

  @type term_index :: non_neg_integer()

  def start(_type, _args) do
    Rafty.Supervisor.start_link()
  end

  def start_server(server_name, cluster_config, fsm_module) do
    Rafty.ServersSupervisor.start_server(server_name, cluster_config, fsm_module)
  end

  def terminate_server(server_name) do
    Rafty.ServersSupervisor.terminate_server(server_name)
  end

  def execute(server_name, timeout \\ 5000) do
    nil
  end

  def query(server_name, timeout \\ 5000) do
    nil
  end

  def status(server_name, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(server_name, :status, timeout) end)
  end

  def leader(server_name, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(server_name, :leader, timeout) end)
  end

  def catch_exit(func) do
    try do
      func.()
    catch
      :exit, {msg, _} when msg in [:noproc, :normal] -> {:error, :noproc}
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end
end
