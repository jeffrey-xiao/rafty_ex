defmodule Rafty.Server.State do
  alias Rafty.Timer

  defstruct id: nil,
            server_state: :follower,
            cluster_config: [],
            leader: nil,
            commit_index: 0,
            last_applied: 0,
            # Finite state machine specific state.
            fsm: nil,
            fsm_state: nil,
            # Leader specific state.
            next_index: %{},
            match_index: %{},
            heartbeat_timer: Timer.new(:heartbeat_timeout),
            # Election specific state.
            votes: MapSet.new(),
            election_timer: Timer.new(:election_timeout),
            # Client requests
            leader_requests: []
end
