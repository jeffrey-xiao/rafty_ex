defmodule RaftyTest do
  use ExUnit.Case
  doctest Rafty

  alias RaftyTest.Util.{Cluster, Stack}
  alias Rafty.Log

  setup do
    Application.stop(:rafty)
    :ok = Application.start(:rafty)

    cluster_config = [
      {:a, node()},
      {:b, node()},
      {:c, node()}
    ]

    args = %{
      cluster_config: cluster_config,
      fsm: Stack,
      log: Log.InMemoryStore
    }

    {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, :a))
    {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, :b))
    {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, :c))
    %{cluster_config: cluster_config}
  end

  test "simple election", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_election(cluster_config)
    assert leader != :timeout

    cluster_config
    |> Enum.each(fn id -> assert Rafty.leader(id) == leader end)
  end

  test "leader failure", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_election(cluster_config)
    assert leader != :timeout
    {server_name, _node_name} = leader
    :ok = Rafty.terminate_server(server_name)

    new_leader = Cluster.wait_for_election(cluster_config)
    assert new_leader != :timeout
    assert leader != new_leader
  end
end
