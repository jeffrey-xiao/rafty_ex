defmodule Rafty.Server.ElectionState do
  alias Rafty.Timer

  defstruct votes: MapSet.new(),
            voted_for: nil,
            timer: Timer.new(:election_timeout)
end
