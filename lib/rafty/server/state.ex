defmodule Rafty.Server.State do
  defstruct id: nil,
            server_state: :follower,
            timer_state: nil,
            cluster_config: [],
            term_index: 0,
            voted_for: nil,
            leader: nil,
            log: [],
            commit_index: 0,
            last_applied: 0,
            # Leader specific state.
            next_index: %{},
            match_index: %{},
            # Candidate specific state.
            votes: MapSet.new()
end
