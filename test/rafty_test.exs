defmodule RaftyTest do
  use ExUnit.Case
  doctest Rafty

  setup do
    Application.stop(:rafty)
    :ok = Application.start(:rafty)
  end

  test "sample" do
    cluster_config = [
      {:a, node()},
      {:b, node()},
      {:c, node()}
    ]

    Rafty.ServersSupervisor.start_server(:a, cluster_config)
    Rafty.ServersSupervisor.start_server(:b, cluster_config)
    Rafty.ServersSupervisor.start_server(:c, cluster_config)
    Process.sleep(5000)
  end
end
