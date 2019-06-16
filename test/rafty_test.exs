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
      log: Log.RocksDBStore,
      ttl: 10 * 60 * 1000 * 1000 * 1000
    }

    File.mkdir!("db")
    on_exit(fn -> File.rm_rf!("db") end)

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

    nil = Cluster.wait_for_replication(cluster_config, 1)
    assert Rafty.status(leader) == {:leader, 1, 1, 1}
  end

  test "simple registration", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    {:ok, 2} = Rafty.register(leader)
    {:ok, 3} = Rafty.register(leader)
  end

  test "simple execution", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    {:ok, client_id} = Rafty.register(leader)
    :ok = Rafty.execute(leader, client_id, {:push, 1})
    :ok = Rafty.execute(leader, client_id, {:push, 2})
    {:ok, 2} = Rafty.execute(leader, client_id, :pop)
    {:ok, 1} = Rafty.execute(leader, client_id, :pop)
  end

  test "cached execution", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    {:ok, client_id} = Rafty.register(leader)
    :ok = Rafty.execute(leader, client_id, {:push, 1})
    ref = make_ref()
    {:ok, 1} = Rafty.execute(leader, client_id, ref, :pop)
    {:ok, 1} = Rafty.execute(leader, client_id, ref, :pop)
    {:ok, nil} = Rafty.execute(leader, client_id, :pop)
  end

  test "simple query", %{cluster_config: cluster_config} do
    leader = Cluster.wait_for_leader(cluster_config)
    assert leader != :timeout

    {:ok, client_id} = Rafty.register(leader)
    0 = Rafty.query(leader, :length)
    0 = Rafty.query(leader, :length)
    :ok = Rafty.execute(leader, client_id, {:push, 1})
    1 = Rafty.query(leader, :length)
    1 = Rafty.query(leader, :length)
    {:ok, 1} = Rafty.execute(leader, client_id, :pop)
    0 = Rafty.query(leader, :length)
    0 = Rafty.query(leader, :length)
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
    |> Enum.take(1)
    |> Enum.each(fn id -> :ok = Rafty.terminate_server(id) end)

    Task.async(fn ->
      Process.sleep(1000)

      cluster_config
      |> Enum.filter(fn id -> id != leader end)
      |> Enum.each(fn {server_name, _node_name} ->
        {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, server_name))
      end)
    end)

    {:ok, client_id} = Rafty.register(leader)
    :ok = Rafty.execute(leader, client_id, {:push, 1})
    {:ok, 1} = Rafty.execute(leader, client_id, :pop)
  end
end
