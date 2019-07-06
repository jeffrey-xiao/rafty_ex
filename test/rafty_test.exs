defmodule RaftyTest do
  use ExUnit.Case, async: true

  alias Rafty.{Log, TestingUtil}
  alias Rafty.TestingUtil.{Cluster, Stack}

  doctest Rafty

  defp clean_db(cluster_config) do
    :ok = Enum.each(cluster_config, fn {server_name, _node_name} ->
      TestingUtil.clean_db(server_name)
    end)
  end

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

    clean_db(cluster_config)
    File.mkdir_p!("db")
    on_exit(fn -> clean_db(cluster_config) end)

    assert {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, :a))
    assert {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, :b))
    assert {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, :c))
    %{cluster_config: cluster_config, args: args}
  end

  test "simple election", %{cluster_config: cluster_config} do
    assert {:ok, leader} = Cluster.wait_for_leader(cluster_config)

    cluster_config
    |> Enum.each(fn id -> assert Rafty.leader(id) == leader end)

    assert Cluster.wait_for_replication(cluster_config, 1) == :ok
    assert Rafty.status(leader) == {:leader, 1, 1, 1}
  end

  test "simple registration", %{cluster_config: cluster_config} do
    assert {:ok, leader} = Cluster.wait_for_leader(cluster_config)
    assert {:ok, 2} = Rafty.register(leader)
    assert {:ok, 3} = Rafty.register(leader)
  end

  test "simple execution", %{cluster_config: cluster_config} do
    assert {:ok, leader} = Cluster.wait_for_leader(cluster_config)
    assert {:ok, client_id} = Rafty.register(leader)
    assert Rafty.execute(leader, client_id, {:push, 1}) == :ok
    assert Rafty.execute(leader, client_id, {:push, 2}) == :ok
    assert Rafty.execute(leader, client_id, :pop) == {:ok, 2}
    assert Rafty.execute(leader, client_id, :pop) == {:ok, 1}
  end

  test "cached execution", %{cluster_config: cluster_config} do
    assert {:ok, leader} = Cluster.wait_for_leader(cluster_config)
    assert {:ok, client_id} = Rafty.register(leader)
    assert Rafty.execute(leader, client_id, {:push, 1}) == :ok
    ref = make_ref()
    assert Rafty.execute(leader, client_id, ref, :pop) == {:ok, 1}
    assert Rafty.execute(leader, client_id, ref, :pop) == {:ok, 1}
    assert Rafty.execute(leader, client_id, :pop) == {:ok, nil}
  end

  test "simple query", %{cluster_config: cluster_config} do
    assert {:ok, leader} = Cluster.wait_for_leader(cluster_config)
    assert {:ok, client_id} = Rafty.register(leader)
    assert Rafty.query(leader, :length) == {:ok, 0}
    assert Rafty.query(leader, :length) == {:ok, 0}
    assert Rafty.execute(leader, client_id, {:push, 1}) == :ok
    assert Rafty.query(leader, :length) == {:ok, 1}
    assert Rafty.query(leader, :length) == {:ok, 1}
    assert Rafty.execute(leader, client_id, :pop) == {:ok, 1}
    assert Rafty.query(leader, :length) == {:ok, 0}
    assert Rafty.query(leader, :length) == {:ok, 0}
  end

  test "leader failure", %{cluster_config: cluster_config} do
    assert {:ok, leader} = Cluster.wait_for_leader(cluster_config)
    assert Rafty.terminate_server(leader) == :ok
    assert {:ok, new_leader} = Cluster.wait_for_leader(cluster_config)
    assert new_leader != :timeout
    assert leader != new_leader
  end

  test "follower failure", %{cluster_config: cluster_config, args: args} do
    assert {:ok, leader} = Cluster.wait_for_leader(cluster_config)

    cluster_config
    |> Enum.filter(fn id -> id != leader end)
    |> Enum.take(1)
    |> Enum.each(fn id -> assert Rafty.terminate_server(id) == :ok end)

    Task.async(fn ->
      Process.sleep(1000)

      cluster_config
      |> Enum.filter(fn id -> id != leader end)
      |> Enum.each(fn {server_name, _node_name} ->
        assert {:ok, _pid} = Rafty.start_server(Map.put(args, :server_name, server_name))
      end)
    end)

    assert {:ok, client_id} = Rafty.register(leader)
    assert Rafty.execute(leader, client_id, {:push, 1}) == :ok
    assert Rafty.execute(leader, client_id, :pop) == {:ok, 1}
  end
end
