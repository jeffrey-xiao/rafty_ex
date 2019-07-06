defmodule Rafty.FSM.ServerTest do
  use ExUnit.Case, async: true

  alias Rafty.FSM.Server
  alias Rafty.TestingUtil.Stack

  doctest Rafty.FSM.Server

  setup do
    server_name = :fsm_server_test
    node_name = node()

    args = %{
      server_name: server_name,
      fsm: Stack,
      ttl: 60,
    }

    {:ok, _pid} = Server.start_link(args)
    %{args: args, id: {server_name, node_name}}
  end

  test "name", %{args: args} do
    assert Server.name(args[:server_name]) == :"FSM.Server.fsm_server_test"
  end

  test "non-existent client", %{id: id} do
    assert Server.execute(id, 0, make_ref(), 0, {:push, 1}) == {:error, :non_existent_client}
  end

  test "execute", %{id: id} do
    assert {:ok, client_id} = Server.register(id, 1, 0)
    assert Server.execute(id, client_id, make_ref(), 0, {:push, 1}) == :ok
    ref = make_ref()
    assert Server.execute(id, client_id, ref, 1, :pop) == {:ok, 1}
    # Cached execution.
    assert Server.execute(id, client_id, ref, 2, :pop) == {:ok, 1}
    # Session expired.
    assert Server.execute(id, client_id, ref, 62, :pop) == {:error, :non_existent_client}
  end

  test "query", %{id: id} do
    assert {:ok, client_id} = Server.register(id, 1, 0)
    assert Server.execute(id, client_id, make_ref(), 0, {:push, 1}) == :ok
    assert Server.query(id, :length) == {:ok, 1}
  end
end
