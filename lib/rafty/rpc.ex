defmodule Rafty.RPC do
  @moduledoc """
  A module that handles sending and broadcasting remote procedure calls (RPCs) specified by the
  Rafty protocol.
  """

  require Logger

  defmodule AppendEntriesRequest do
    @moduledoc """
    A request for appending entries to the Raft log.
    """

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

    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            prev_log_index: Rafty.log_index(),
            prev_log_term_index: Rafty.log_index() | nil,
            entries: [Rafty.Log.Entry.t()],
            leader_commit_index: Rafty.log_index()
          }
  end

  defmodule AppendEntriesResponse do
    @moduledoc """
    A response to `Rafty.RPC.AppendEntriesRequest`.
    """

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

    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            last_applied: Rafty.log_index(),
            last_log_index: Rafty.log_index(),
            success: bool()
          }
  end

  defmodule RequestVoteRequest do
    @moduledoc """
    A request for a vote in a Raft election.
    """

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

    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            last_log_index: Rafty.log_index(),
            last_log_term_index: Rafty.term_index()
          }
  end

  defmodule RequestVoteResponse do
    @moduledoc """
    A response to `Rafty.RPC.RequestVoteRequest`.
    """

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

    @type t :: %__MODULE__{
            from: Rafty.id(),
            to: Rafty.opt_id(),
            term_index: Rafty.term_index(),
            vote_granted: bool()
          }
  end

  @doc """
  Sends `rpc` to all servers specified in `neighbours`. Each `rpc` will have its `to` field set
  correspondingly.
  """
  @spec broadcast(Rafty.rpc(), [Rafty.id()]) :: :ok
  def broadcast(rpc, neighbours) do
    neighbours
    |> Enum.each(fn neighbour ->
      send_rpc(%{rpc | to: neighbour})
    end)
  end

  @doc """
  Sends `rpc` to the server specified by `rpc.to`.
  """
  @spec send_rpc(Rafty.rpc()) :: DynamicSupervisor.on_start_child()
  def send_rpc(rpc) do
    Task.Supervisor.start_child(Rafty.RPC.Supervisor, fn -> send_rpc_impl(rpc) end)
  end

  @spec send_rpc_impl(Rafty.rpc()) :: :ok | {:error, term()}
  defp send_rpc_impl(rpc) do
    rpc.to
    |> GenServer.call(rpc)
    |> case do
      %AppendEntriesResponse{} = response -> GenServer.cast(rpc.from, response)
      %RequestVoteResponse{} = response -> GenServer.cast(rpc.from, response)
      response -> Logger.error("Expected response: #{inspect(rpc)} yielded #{response}")
    end
  end
end
