defmodule Rafty do
  use Application

  @type server_name :: atom()
  @type node_name :: atom()
  @type id :: {server_name(), node_name()}
  @type server_state :: :follower | :candidate | :leader
  @type args :: %{
          server_name: server_name(),
          node_name: node_name(),
          fsm: atom(),
          log: atom()
        }
  @type catch_exit_error() :: {:error, :noproc | :timeout}

  @impl Application
  def start(_type, _args) do
    Rafty.Supervisor.start_link()
  end

  @spec start_server(args()) :: DynamicSupervisor.on_start_child()
  def start_server(args) do
    Rafty.ServersSupervisor.start_server(args)
  end

  @spec terminate_server(server_name()) :: :ok | {:error, :not_found}
  def terminate_server(server_name) do
    Rafty.ServersSupervisor.terminate_server(server_name)
  end

  @spec execute(server_name(), term(), timeout()) :: term() | catch_exit_error()
  def execute(server_name, payload, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(server_name, {:execute, payload}, timeout) end)
  end

  @spec query(server_name(), term(), timeout()) :: term() | catch_exit_error()
  def query(server_name, payload, timeout \\ 5000) do
    nil
  end

  @spec status(server_name(), timeout()) ::
          {server_state(), non_neg_integer(), non_neg_integer()} | catch_exit_error()
  def status(server_name, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(server_name, :status, timeout) end)
  end

  @spec leader(server_name(), timeout()) :: id() | nil | catch_exit_error()
  def leader(server_name, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(server_name, :leader, timeout) end)
  end

  @spec catch_exit((() -> ret)) :: ret when ret: term() | catch_exit_error()
  def catch_exit(func) do
    func.()
  catch
    :exit, {msg, _} when msg in [:noproc, :normal] -> {:error, :noproc}
    :exit, {:timeout, _} -> {:error, :timeout}
  end
end
