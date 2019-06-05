defmodule RaftyTest.Util.Cluster do
  def wait_for_election(cluster_config, timeout \\ 250, retries \\ 3) do
    if retries == 0 do
      :timeout
    else
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
        nil ->
          wait_for_election(cluster_config, timeout, retries - 1)

        leader ->
          leader
      end
    end
  end
end
