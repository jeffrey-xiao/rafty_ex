defmodule Rafty.RPC do
  defmodule AppendEntriesRequest do
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

  def broadcast(rpc_type, rpc, neighbours) do
    require Logger
    IO.inspect(neighbours)
    neighbours
    |> Enum.each(fn neighbour ->
      IO.puts("NEIGHBOUR IS #{inspect(neighbour)}")
      send_rpc(rpc_type, %{rpc | to: neighbour})
    end)
  end

  def send_rpc(rpc_type, rpc) do
    require Logger
    Logger.info("#{inspect(rpc.from)} sending to #{inspect(rpc.to)} message #{inspect(rpc)}")
    GenServer.cast(rpc.to, {rpc_type, rpc})
  end
end
