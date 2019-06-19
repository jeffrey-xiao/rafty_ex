defmodule Rafty do
  @moduledoc """
  An implementation of the Raft consensus algorithm written in pure Elixir. For learning purposes
  only and not production use.
  """

  use Application

  @typedoc """
  The name of a server. Should be unique among all servers.
  """
  @type server_name :: atom()

  @typedoc """
  The name of a node.
  """
  @type node_name :: atom()

  @typedoc """
  A tuple `{server_name, node_name}` that represents the unique id of a server.
  """
  @type id :: {server_name(), node_name()}

  @typedoc """
  A possibly `nil` id of a server.
  """
  @type opt_id :: id() | nil

  @typedoc """
  The state of server server. A server is either a follower, candidate, or a leader.
  """
  @type server_state :: :follower | :candidate | :leader

  @typedoc """
  The configuration of a server.
  """
  @type args :: %{
          server_name: server_name(),
          node_name: node_name(),
          fsm: atom(),
          log: atom()
        }

  @typedoc """
  An error returned when a server is not a leader. This error provides a hint to the leader, if any.
  """
  @type not_leader :: {:not_leader, id() | nil}

  @typedoc """
  An error caught when a request exits.
  """
  @type catch_exit_error :: {:error, :noproc | :timeout}

  @typedoc """
  An error caught when a request exits with the associated reference to the request.
  """
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

  @doc """
  Starts a new server on the current server with the specified arguments.
  """
  @spec start_server(args()) :: DynamicSupervisor.on_start_child()
  def start_server(args) do
    Rafty.ServersSupervisor.start_server(args)
  end

  @doc """
  Terminates a server with the specified id.
  """
  @spec terminate_server(id()) :: :ok | {:error, :not_found}
  def terminate_server(id) do
    Rafty.ServersSupervisor.terminate_server(id)
  end

  @doc """
  Registers a client on the server with the specified id. If the server is not a leader, this
  function will return the leader of the server, possibly `nil`. Clients must call `register()`
  before calling `execute()`.
  """
  @spec register(id(), timeout()) :: client_id()
  def register(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :register, timeout) end)
  end

  @doc """
  Executes a command that may modify the Raft state machine on the server with the specified id. If
  the server is not a leader, this function will return the leader of the server, possibly `nil`.
  Clients must specify the client id created by `register()` when calling `execute()`. If
  `execute()` times out, it will return the reference associated with the execute call. If a client
  wants to retry the command, they _must_ supply this reference in subsequent retries. Additionally,
  if a client is retrying a command, they must not make any execute commands with different
  references or the command may be executed twice.
  """
  @spec execute(id(), client_id(), reference(), term(), timeout()) ::
          term() | not_leader() | catch_exit_ref_error()
  def execute(id, client_id, ref \\ make_ref(), payload, timeout \\ 5000) do
    catch_exit_ref(
      fn -> GenServer.call(id, {:execute, client_id, ref, payload}, timeout) end,
      ref
    )
  end

  @doc """
  Executies a read-only query of the Raft state machine on the server with the specified id. If the
  server is not a leader, this function will return the leader of the server, possibly `nil`. Any
  query should not mutate the Raft state machine because it does not persist in the Raft log, so
  server failures may cause Raft state machine inconsistencies.
  """
  @spec query(id(), term(), timeout()) :: term() | not_leader() | catch_exit_error()
  def query(id, payload, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, {:query, payload}, timeout) end)
  end

  @doc """
  Returns a tuple `{server_state, term_index, commit_index, last_applied}` of the server with the
  specified id.
  """
  @spec status(id(), timeout()) ::
          {server_state(), term_index(), log_index(), log_index()} | catch_exit_error()
  def status(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :status, timeout) end)
  end

  @doc """
  Returns the leader of the server with the specified id. If this function does not timeout, it will
  not return nil. If the server has no leader at the time of the call, it will wait until a leader
  has been elected before replying.
  """
  @spec leader(id(), timeout()) :: Rafty.id() | nil | catch_exit_error()
  def leader(id, timeout \\ 5000) do
    catch_exit(fn -> GenServer.call(id, :leader, timeout) end)
  end

  @spec catch_exit((() -> ret)) :: ret when ret: term() | catch_exit_error()
  defp catch_exit(func) do
    func.()
  catch
    :exit, {msg, _} when msg in [:noproc, :normal] -> {:error, :noproc}
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  @spec catch_exit_ref((() -> ret), reference()) :: ret when ret: term() | catch_exit_ref_error()
  defp catch_exit_ref(func, ref) do
    func.()
  catch
    :exit, {msg, _} when msg in [:noproc, :normal] -> {:error, :noproc}
    :exit, {:timeout, _} -> {:error, :timeout, ref}
  end
end
