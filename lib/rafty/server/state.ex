defmodule Rafty.Server.State do
  defstruct current_term_index: 0,
            voted_for: nil,
            log: [],
            commit_index: 0,
            last_applied: 0,
            server_name: nil,
            node_name: nil,
            server_state: :follower,
            neighbours: [],
            timer_state: nil,
            # Leader specific state.
            next_index: %{},
            match_index: %{},
            # Candidate specific state.
            votes: %{}
end
