defmodule RaftyTest.Util.Cluster do
  alias RaftyTest.Util

  def wait_for_election(cluster_config) do
    Util.succeed_soon(fn timeout ->
      cluster_config
      |> Enum.map(fn id -> Task.async(fn -> Rafty.leader(id, timeout) end) end)
      |> Enum.map(fn task -> Task.await(task) end)
      |> Enum.filter(fn resp ->
        case resp do
          {:error, _msg} -> false
          _ -> true
        end
      end)
      |> Enum.find(fn leader -> leader != nil end)
      |> case do
        nil -> {nil, false}
        leader -> {leader, true}
      end
    end)
  end
end
