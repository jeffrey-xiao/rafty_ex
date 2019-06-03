defmodule RaftyTest do
  use ExUnit.Case
  doctest Rafty

  alias RaftyTest.Util.{Cluster, Stack}
  alias Rafty.Log

  setup do
    Application.stop(:rafty)
    :ok = Application.start(:rafty)
  end

  test "simple election" do
    cluster_config = [
      {:a, node()},
      {:b, node()},
      {:c, node()}
    ]

    Rafty.start_server(:a, cluster_config, Stack, Log.InMemoryStore)
    Rafty.start_server(:b, cluster_config, Stack, Log.InMemoryStore)
    Rafty.start_server(:c, cluster_config, Stack, Log.InMemoryStore)

    leader = Cluster.wait_for_election(cluster_config)

    cluster_config
    |> Enum.each(fn id -> assert Rafty.leader(id) == leader end)
  end
end
