defmodule Rafty.Server.State do
  alias Rafty.{Server.ElectionState, Timer}

  defstruct id: nil,
            server_state: :follower,
            cluster_config: [],
            term_index: 0,
            leader: nil,
            log: [],
            commit_index: 0,
            last_applied: 0,
            # Finite state machine specific state.
            fsm_module: nil,
            fsm: nil,
            # Leader specific state.
            next_index: %{},
            match_index: %{},
            heartbeat_timer: Timer.new(:heartbeat_timeout),
            # Election specific state.
            votes: MapSet.new(),
            election_timer: Timer.new(:election_timeout),
            voted_for: nil,
            # Client requests
            leader_requests: []
end
