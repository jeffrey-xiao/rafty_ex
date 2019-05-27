defmodule Rafty.RPC do
  defmodule AppendEntriesRequest do
    defstruct [
      :term_index,
      :leader_id,
      :prev_log_index,
      :prev_log_term_index,
      :entries,
      :leader_commit_index
    ]
  end

  defmodule AppendEntriesResponse do
    defstruct [
      :term_index,
      :success
    ]
  end

  defmodule RequestVoteRequest do
    defstruct [
      :term_index,
      :candidate_id,
      :last_log_index,
      :last_log_term_index
    ]
  end

  defmodule RequestVoteResponse do
    defstruct [
      :term_index,
      :vote_granted
    ]
  end

  def broadcast(rpc) do
    nil
  end

  def send_rpc(rpc) do
    nil
  end
end
