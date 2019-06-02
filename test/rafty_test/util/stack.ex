defmodule RaftyTest.Util.Stack do
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
