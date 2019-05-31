defmodule Rafty.Server.State do
  alias Rafty.{Server.ElectionState, Timer}

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
            fsm_module: nil,
            fsm: nil,
            # Leader specific state.
            next_index: %{},
            match_index: %{},
            heartbeat_timer: Timer.new(:heartbeat_timeout),
            # Election specific state.
            election_state: %ElectionState{}
end
