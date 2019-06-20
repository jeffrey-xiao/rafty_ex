defmodule RaftyTest.Util.Stack do
  @moduledoc false

  @behaviour Rafty.FSM

  @impl Rafty.FSM
  def init, do: []

  @impl Rafty.FSM
  def execute(state, {:push, val}), do: {:ok, [val | state]}

  @impl Rafty.FSM
  def execute(state, :pop) do
    case state do
      [] -> {{:ok, nil}, state}
      [head | tail] -> {{:ok, head}, tail}
    end
  end

  @impl Rafty.FSM
  def query(state, :length), do: length(state)
end
