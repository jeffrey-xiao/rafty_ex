defmodule RaftyTest do
  use ExUnit.Case
  doctest Rafty

  alias RaftyTest.Util.{Cluster, Stack}

  setup do
    Application.stop(:rafty)
    :ok = Application.start(:rafty)
  end

  test "simple" do
    cluster_config = [
      {:a, node()},
      {:b, node()},
      {:c, node()}
    ]

    Rafty.start_server(:a, cluster_config, Stack)
    Rafty.start_server(:b, cluster_config, Stack)
    Rafty.start_server(:c, cluster_config, Stack)

    leader = Cluster.wait_for_election(cluster_config)

    cluster_config
    |> Enum.each(fn id -> assert Rafty.leader(id) == leader end)
  end
end
