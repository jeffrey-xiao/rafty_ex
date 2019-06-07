defmodule Rafty.Server.State do
  alias Rafty.Timer

  @type t :: %__MODULE__{
          server_state: Rafty.server_state(),
          cluster_config: [Rafty.id()],
          leader: Rafty.id() | nil,
          commit_index: non_neg_integer(),
          last_applied: non_neg_integer(),
          fsm: module(),
          fsm_state: term(),
          next_index: %{atom() => non_neg_integer()},
          match_index: %{atom() => non_neg_integer()},
          heartbeat_timer: Timer.t(),
          votes: MapSet.t(Rafty.id()),
          election_timer: Timer.t(),
          leader_requests: [GenServer.from()],
          execute_requests: [{GenServer.from(), non_neg_integer()}]
        }
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
            leader_requests: [],
            execute_requests: []
end
