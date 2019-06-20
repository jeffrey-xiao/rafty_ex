defmodule RaftyTest.Util.Cluster do
  @moduledoc false

  alias RaftyTest.Util

  def wait_for_leader(cluster_config) do
    Util.succeed_soon(fn ->
      resps =
        cluster_config
        |> Enum.map(fn id -> {Task.async(fn -> Rafty.leader(id) end), id} end)
        |> Enum.map(fn {task, id} -> {Task.await(task), id} end)
        |> Enum.filter(fn {resp, id} ->
          case resp do
            {:error, _msg} -> false
            nil -> false
            _ -> true
          end
        end)

      leader_id =
        resps
        |> Enum.find(fn {leader, id} -> leader == id end)
        |> case do
          nil -> nil
          {leader_id, id} -> leader_id
        end

      count = Enum.count(resps, fn {leader, id} -> leader_id == leader end)

      if count >= (cluster_config |> length |> div(2)) + 1,
        do: {:ok, {:ok, leader_id}},
        else: :retry
    end)
  end

  def wait_for_replication(cluster_config, log_index) do
    Util.succeed_soon(fn ->
      commit_indexes =
        cluster_config
        |> Enum.map(fn id -> Task.async(fn -> Rafty.status(id) end) end)
        |> Enum.map(fn task -> Task.await(task) end)
        |> Enum.filter(fn resp ->
          case resp do
            {:error, _msg} -> false
            _ -> true
          end
        end)
        |> Enum.map(fn {_server_state, _term_index, _commit_index, applied_index} ->
          applied_index
        end)

      index = cluster_config |> length |> div(2)
      commit_index = Enum.at(commit_indexes, index)

      if log_index <= commit_index,
        do: {:ok, :ok},
        else: :retry
    end)
  end
end
