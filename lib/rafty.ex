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
  @type catch_exit_error :: {:error, :noproc | :timeout}
  @type(catch_exit_ref_error :: {:error, :noproc}, {:error, :timeout, reference()})
  @type rpc ::
          Rafty.RPC.AppendEntriesRequest.t()
          | Rafty.RPC.AppendEntriesResponse.t()
          | Rafty.RPC.RequestVoteRequest.t()
          | Rafty.RPC.RequestVoteResponse.t()
  @type log_index :: non_neg_integer()
  @type term_index :: non_neg_integer()
  @type client_id :: non_neg_integer()
  @type timestamp :: integer()

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

  @spec register(id(), timeout()) :: client_id()
  def register(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :register, timeout) end)
  end

  @spec execute(id(), client_id(), reference(), term(), timeout()) ::
          term() | {:not_leader, Rafty.id()} | catch_exit_error()
  def execute(id, client_id, ref \\ make_ref(), payload, timeout \\ 5000) do
    catch_exit_ref(
      fn -> GenServer.call(id, {:execute, client_id, ref, payload}, timeout) end,
      ref
    )
  end

  @spec query(id(), term(), timeout()) :: term() | {:not_leader, Rafty.id()} | catch_exit_error()
  def query(id, payload, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, {:query, payload}, timeout) end)
  end

  @spec status(id(), timeout()) ::
          {server_state(), term_index(), log_index(), log_index()} | catch_exit_error()
  def status(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :status, timeout) end)
  end

  @spec leader(id(), timeout()) :: Rafty.id() | catch_exit_error()
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

  @spec catch_exit_ref((() -> ret), reference()) :: ret when ret: term() | catch_exit_ref_error()
  def catch_exit_ref(func, ref) do
    func.()
  catch
    :exit, {msg, _} when msg in [:noproc, :normal] -> {:error, :noproc}
    :exit, {:timeout, _} -> {:error, :timeout, ref}
  end
end
