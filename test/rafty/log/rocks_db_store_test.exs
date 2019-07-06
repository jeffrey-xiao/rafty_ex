defmodule Rafty.Log.RocksDBStoreTest do
  use ExUnit.Case, async: true

  alias Rafty.Log.{Server, RocksDBStore}
  alias Rafty.TestingUtil

  doctest Rafty.Log.RocksDBStore

  setup do
    server_name = :rocks_db_store_test
    node_name = node()

    args = %{
      server_name: server_name,
      log: RocksDBStore
    }

    File.mkdir_p!("db")
    on_exit(fn -> File.rm_rf!(Path.join("db", Atom.to_string(server_name))) end)
    {:ok, pid} = Server.start_link(args)
    %{pid: pid, args: args, id: {server_name, node_name}}
  end

  test "name", %{args: args} do
    assert Server.name(args[:server_name]) == :"Log.Server.rocks_db_store_test"
  end

  test "term index", %{args: args, id: id} do
    assert Server.get_term_index(id) == 0
    assert Server.increment_term_index(id) == 1
    assert Server.get_term_index(id) == 1
    assert Server.set_term_index(id, 2) == :ok
    assert Server.get_term_index(id) == 2
    Server.stop(id)
    {:ok, _pid} = Server.start_link(args)
    assert Server.get_term_index(id) == 2
    Server.stop(id)
  end

  test "voted for", %{args: args, id: id} do
    assert Server.get_voted_for(id) == nil
    assert Server.set_voted_for(id, :a) == :ok
    assert Server.get_voted_for(id) == :a
    Server.stop(id)
    {:ok, _pid} = Server.start_link(args)
    assert Server.get_voted_for(id) == :a
    Server.stop(id)
  end

  test "entries", %{id: id} do
    assert Server.get_entry(id, 1) == nil
    assert Server.length(id) == 0
    e1 = TestingUtil.new_entry(1, 1, nil)
    e2 = TestingUtil.new_entry(2, 2, nil)
    assert Server.append_entries(id, [e1, e2], 0) == :ok
    assert Server.get_entry(id, 1) == e1
    assert Server.get_entries(id, 1) == [e1, e2]
    assert Server.length(id) == 2
    Server.stop(id)
  end

  test "override entries", %{id: id} do
    e1 = TestingUtil.new_entry(1, 1, nil)
    old_e2 = TestingUtil.new_entry(2, 2, nil)
    old_e3 = TestingUtil.new_entry(3, 3, nil)
    new_e2 = TestingUtil.new_entry(3, 3, nil)
    assert Server.append_entries(id, [e1, old_e2, old_e3], 0) == :ok
    assert Server.append_entries(id, [e1, new_e2], 0) == :ok
    assert Server.get_entries(id, 1) == [e1, new_e2]
    assert Server.length(id) == 2
    Server.stop(id)
  end

  test "missing entries", %{id: id} do
    e1 = TestingUtil.new_entry(1, 1, nil)
    e2 = TestingUtil.new_entry(2, 2, nil)
    e3 = TestingUtil.new_entry(3, 3, nil)
    assert Server.append_entries(id, [e1, e2, e3], 0) == :ok
    assert Server.append_entries(id, [e1, e2], 0) == :ok
    assert Server.get_entries(id, 1) == [e1, e2, e3]
    assert Server.length(id) == 3
    Server.stop(id)
  end

  test "length", %{args: args, id: id} do
    e1 = TestingUtil.new_entry(1, 1, nil)
    e2 = TestingUtil.new_entry(2, 2, nil)
    assert Server.append_entries(id, [e1, e2], 0) == :ok
    assert Server.length(id) == 2
    Server.stop(id)
    {:ok, _pid} = Server.start_link(args)
    assert Server.length(id) == 2
    Server.stop(id)
  end
end