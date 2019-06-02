defmodule RaftyTest do
  use ExUnit.Case
  doctest Rafty

  defmodule Stack do
    @behaviour Rafty.FSM

    @impl Rafty.FSM
    def init(), do: []

    @impl Rafty.FSM
    def execute(state, {:push, val}), do: {:ok, [val] ++ state}

    @impl Rafty.FSM
    def execute(state, :pop) do
      case state do
        [] -> {nil, state}
        [head | tail] -> {head, tail}
      end
    end

    @impl Rafty.FSM
    def query(state, :length), do: length(state)
  end

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
    Process.sleep(5000)
  end
end
