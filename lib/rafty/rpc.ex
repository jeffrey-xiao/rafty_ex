defmodule Rafty.RPC do
  require Logger

  defmodule AppendEntriesRequest do
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
    defstruct [
      :from,
      :to,
      :term_index,
      :last_log_index,
      :last_log_term_index
    ]
  end

  defmodule RequestVoteResponse do
    defstruct [
      :from,
      :to,
      :term_index,
      :vote_granted
    ]
  end

  def broadcast(rpc, neighbours) do
    neighbours
    |> Enum.each(fn neighbour ->
      send_rpc(%{rpc | to: neighbour})
    end)
  end

  def send_rpc(rpc) do
    Task.Supervisor.start_child(Rafty.RPC.Supervisor, fn -> send_rpc_impl(rpc) end)
  end

  def send_rpc_impl(rpc) do
    GenServer.call(rpc.to, rpc)
    |> case do
      %AppendEntriesResponse{} = response -> GenServer.cast(rpc.from, response)
      %RequestVoteResponse{} = response -> GenServer.cast(rpc.from, response)
      response -> Logger.error("Expected response: #{inspect(rpc)} yielded #{response}")
    end
  end
end
