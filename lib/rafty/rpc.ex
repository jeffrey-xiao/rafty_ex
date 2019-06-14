defmodule Rafty.RPC do
  require Logger

  defmodule AppendEntriesRequest do
    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            prev_log_index: Rafty.log_index(),
            prev_log_term_index: Rafty.log_index() | nil,
            entries: [Rafty.Log.Entry.t()],
            leader_commit_index: Rafty.log_index()
          }
    @enforce_keys [
      :from,
      :term_index,
      :prev_log_index,
      :prev_log_term_index,
      :entries,
      :leader_commit_index
    ]
    defstruct [
      :from,
      :to,
      :term_index,
      :prev_log_index,
      :prev_log_term_index,
      :entries,
      :leader_commit_index
    ]
  end

  defmodule AppendEntriesResponse do
    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            last_log_index: Rafty.log_index(),
            success: bool()
          }
    @enforce_keys [
      :from,
      :term_index,
      :last_log_index,
      :success
    ]
    defstruct [
      :from,
      :to,
      :term_index,
      :last_applied,
      :last_log_index,
      :success
    ]
  end

  defmodule RequestVoteRequest do
    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            last_log_index: Rafty.log_index(),
            last_log_term_index: Rafty.term_index()
          }
    @enforce_keys [
      :from,
      :term_index,
      :last_log_index,
      :last_log_term_index
    ]
    defstruct [
      :from,
      :to,
      :term_index,
      :last_log_index,
      :last_log_term_index
    ]
  end

  defmodule RequestVoteResponse do
    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            vote_granted: bool()
          }
    @enforce_keys [
      :from,
      :term_index,
      :vote_granted
    ]
    defstruct [
      :from,
      :to,
      :term_index,
      :vote_granted
    ]
  end

  @spec broadcast(Rafty.rpc(), [Rafty.id()]) :: :ok
  def broadcast(rpc, neighbours) do
    neighbours
    |> Enum.each(fn neighbour ->
      send_rpc(%{rpc | to: neighbour})
    end)
  end

  @spec send_rpc(Rafty.rpc()) :: DynamicSupervisor.on_start_child()
  def send_rpc(rpc) do
    Task.Supervisor.start_child(Rafty.RPC.Supervisor, fn -> send_rpc_impl(rpc) end)
  end

  @spec send_rpc_impl(Rafty.rpc()) :: :ok | {:error, term()}
  def send_rpc_impl(rpc) do
    rpc.to
    |> GenServer.call(rpc)
    |> case do
      %AppendEntriesResponse{} = response -> GenServer.cast(rpc.from, response)
      %RequestVoteResponse{} = response -> GenServer.cast(rpc.from, response)
      response -> Logger.error("Expected response: #{inspect(rpc)} yielded #{response}")
    end
  end
end
