defmodule RaftyTest.Util.Cluster do
  alias RaftyTest.Util

  def wait_for_election(cluster_config) do
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
        do: {leader_id, true},
        else: {nil, false}
    end)
  end
end
