defmodule RaftyTest.Util.Cluster do
  alias RaftyTest.Util

  def wait_for_election(cluster_config) do
    Util.succeed_soon(fn ->
      cluster_config
      |> Enum.map(fn id -> {Task.async(fn -> Rafty.leader(id) end), id} end)
      |> Enum.map(fn {task, id} -> {Task.await(task), id} end)
      |> Enum.filter(fn {resp, id} ->
        case resp do
          {:error, _msg} -> false
          resp -> true
        end
      end)
      |> Enum.find(fn {leader, id} -> leader == id end)
      |> case do
        nil -> {nil, false}
        {leader, id} -> {leader, true}
      end
    end)
  end
end
