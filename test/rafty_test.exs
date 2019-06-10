defmodule RaftyTest do
  use ExUnit.Case
  doctest Rafty

  alias Rafty.Log
  alias RaftyTest.Util.{Cluster, Stack}

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
    %{cluster_config: cluster_config, args: args}
  end

  test "simple election", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    cluster_config
    |> Enum.each(fn id -> assert Rafty.leader(id) == leader end)
  end

  test "simple registration" do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    2 = Rafty.register(leader)
    3 = Rafty.register(leader)
  end

  test "simple state", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    :ok = Rafty.execute(leader, {:push, 1})
    :ok = Rafty.execute(leader, {:push, 2})
    2 = Rafty.execute(leader, :pop)
    1 = Rafty.execute(leader, :pop)
  end

  test "leader failure", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout
    :ok = Rafty.terminate_server(leader)

    new_leader = Cluster.wait_for_leader(cluster_config)
    assert new_leader != :timeout
    assert leader != new_leader
  end

  test "follower failure", %{cluster_config: cluster_config, args: args} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    cluster_config
    |> Enum.filter(fn id -> id != leader end)
    |> Enum.each(fn id -> :ok = Rafty.terminate_server(id) end)

    Task.async(fn ->
      Process.sleep(1000)

      cluster_config
      |> Enum.filter(fn id -> id != leader end)
      |> Enum.each(fn {server_name, _node_name} ->
        {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, server_name))
      end)
    end)

    :ok = Rafty.execute(leader, {:push, 1})
    1 = Rafty.execute(leader, :pop)
  end
end
