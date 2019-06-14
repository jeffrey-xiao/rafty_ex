defmodule Rafty do
  use Application

  @type server_name :: atom()
  @type node_name :: atom()
  @type id :: {server_name(), node_name()}
  @type opt_id :: id() | nil
  @type server_state :: :follower | :candidate | :leader
  @type args :: %{
          server_name: server_name(),
          node_name: node_name(),
          fsm: atom(),
          log: atom()
        }
  @type catch_exit_error() :: {:error, :noproc | :timeout}
  @type rpc() ::
          Rafty.RPC.AppendEntriesRequest.t()
          | Rafty.RPC.AppendEntriesResponse.t()
          | Rafty.RPC.RequestVoteRequest.t()
          | Rafty.RPC.RequestVoteResponse.t()

  @impl Application
  def start(_type, _args) do
    Rafty.Supervisor.start_link()
  end

  @spec start_server(args()) :: DynamicSupervisor.on_start_child()
  def start_server(args) do
    Rafty.ServersSupervisor.start_server(args)
  end

  @spec terminate_server(id()) :: :ok | {:error, :not_found}
  def terminate_server(id) do
    Rafty.ServersSupervisor.terminate_server(id)
  end

  @spec register(id(), timeout()) :: non_neg_integer()
  def register(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :register, timeout) end)
  end

  @spec execute(id(), term(), timeout()) :: term() | catch_exit_error()
  def execute(id, payload, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, {:execute, payload}, timeout) end)
  end

  @spec query(id(), term(), timeout()) :: term() | catch_exit_error()
  def query(id, payload, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, {:execute, payload}, timeout) end)
  end

  @spec status(server_name(), timeout()) ::
          {id(), non_neg_integer(), non_neg_integer()} | catch_exit_error()
  def status(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :status, timeout) end)
  end

  @spec leader(id(), timeout()) :: id() | nil | catch_exit_error()
  def leader(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :leader, timeout) end)
  end

  @spec catch_exit((() -> ret)) :: ret when ret: term() | catch_exit_error()
  def catch_exit(func) do
    func.()
  catch
    :exit, {msg, _} when msg in [:noproc, :normal] -> {:error, :noproc}
    :exit, {:timeout, _} -> {:error, :timeout}
  end
end
