defmodule Rafty.Server do
  require Logger
  use GenServer
  alias Rafty.{Server.State, Server.ElectionState, RPC, Timer}

  @election_timeout_low 250
  @election_timeout_high 500
  @heartbeat_timeout 100

  def start_link({server_name, _node_name, _cluster_config, _fsm_module} = args) do
    GenServer.start_link(__MODULE__, args, name: server_name)
  end

  def init({server_name, node_name, cluster_config, fsm_module}) do
    Logger.info("#{inspect({server_name, node_name})}: Started")
    :random.seed(:erlang.now())

    {:ok,
     %State{
       id: {server_name, node_name},
       cluster_config: cluster_config,
       fsm_module: fsm_module,
       fsm: fsm_module.init()
     }
     |> convert_to_follower(0)
     |> reset_timers()}
  end

  def handle_call(%RPC.AppendEntriesRequest{} = rpc, _from, state) do
    Logger.info("#{inspect(state.id)}: Received append_entries_request")

    state =
      if rpc.term_index >= state.term_index and state.server_state != :follower do
        %{state | leader: rpc.from} |> convert_to_follower(rpc.term_index)
      else
        state
      end

    # TODO: Instead of returning a boolean for success, return the index of the first mismatch for
    # efficiency.
    success =
      cond do
        # Section 5.1: Server rejects all rejects with stale term numbers.
        rpc.term_index < state.term_index ->
          false

        # Section 5.3: Fail if entry with index `prev_log_index` is not in log.
        # TODO: This should change when we implement snapshotting and compaction.
        length(state.log) < rpc.prev_log_term_index ->
          false

        # Section 5.3: Fail if entry does not the same term.
        true ->
          case hd(state.log) do
            nil -> rpc.prev_log_term_index == nil
            entry -> entry.term_index == rpc.prev_log_term_index
          end
      end

    # TODO: This should change when we implement snapshotting and compaction.
    {new_log, new_commit_index} =
      if success do
        # TODO: This should change when we implement snapshotting and compaction.
        {head, tail} = Enum.split(state.log, rpc.prev_log_index)

        {
          head ++ merge_logs(tail, rpc.entries),
          min(max(rpc.leader_commit_index, state.commit_index), length(state.log))
        }
      else
        {state.log, state.commit_index}
      end

    state =
      %{state | log: new_log, commit_index: new_commit_index}
      |> advance_log()
      |> reset_timers()

    {:reply,
     %RPC.AppendEntriesResponse{
       from: rpc.to,
       to: rpc.from,
       term_index: state.term_index,
       last_applied: state.last_applied,
       last_log_index: length(state.log),
       success: success
     }, state}
  end

  def handle_call(%RPC.RequestVoteRequest{} = rpc, _from, state) do
    Logger.info("#{inspect(state.id)}: Received request_vote_request")

    state =
      if rpc.term_index > state.term_index,
        do: convert_to_follower(state, rpc.term_index),
        else: state

    vote_granted =
      cond do
        # Section 5.1: Server rejects all requests with stale term numbers.
        rpc.term_index < state.term_index -> false
        # Candidate has already voted.
        state.voted_for != nil and state.voted_for != rpc.from -> false
        # Section 5.4.1: Candidate log must be be at least up-to-date as current log.
        state.term_index > rpc.last_log_term_index -> false
        # TODO: This should change when we implement snapshotting and compaction.
        length(state.log) > rpc.last_log_index -> false
        true -> true
      end

    new_voted_for = if vote_granted, do: rpc.from, else: state.voted_for

    {:reply,
     %RPC.RequestVoteResponse{
       from: rpc.to,
       to: rpc.from,
       term_index: state.term_index,
       vote_granted: vote_granted
     }, %{state | voted_for: new_voted_for} |> reset_timers()}
  end

  def handle_cast(%RPC.AppendEntriesResponse{} = rpc, state) do
    Logger.info("#{inspect(state.id)}: Received append_entries_response")

    state =
      if rpc.term_index > state.term_index,
        do: convert_to_follower(state, rpc.term_index),
        else: state

    {new_next_index, new_match_index} =
      if rpc.success do
        {Map.put(state.next_index, rpc.from, rpc.last_log_index + 1),
         Map.put(state.match_index, rpc.from, rpc.last_applied)}
      else
        {state.next_index, state.match_index}
      end

    {:noreply, %{state | next_index: new_next_index, match_index: new_match_index}}
  end

  def handle_cast(%RPC.RequestVoteResponse{} = rpc, state) do
    Logger.info("#{inspect(state.id)}: Received request_vote_response")

    state =
      if rpc.term_index > state.term_index,
        do: convert_to_follower(state, rpc.term_index),
        else: state

    state = if rpc.vote_granted, do: add_vote(state, rpc.from), else: state
    {:noreply, state |> reset_timers()}
  end

  def handle_info({:election_timeout, ref}, %{election_state: %{timer: %{ref: ref}}} = state) do
    Logger.info("#{inspect(state.id)}: Received election_timeout")
    {:noreply, state |> convert_to_candidate() |> reset_timers()}
  end

  def handle_info({:election_timeout, _ref}, state), do: {:noreply, state}

  def handle_info({:heartbeat_timeout, ref}, %{heartbeat_timer: %{ref: ref}} = state) do
    Logger.info("#{inspect(state.id)}: Received heartbeat_timer")
    broadcast_append_entries(state)
    {:noreply, state |> reset_timers()}
  end

  def handle_info({:heartbeat_timeout, _ref}, state), do: {:noreply, state}

  defp broadcast_append_entries(state) do
    state
    |> neighbours()
    |> Enum.each(fn neighbour ->
      {prev_log_index, prev_log_term_index, entries} =
        split_log(state.log, state.next_index[neighbour])

      RPC.send_rpc(%RPC.AppendEntriesRequest{
        from: state.id,
        to: neighbour,
        term_index: state.term_index,
        prev_log_index: prev_log_index,
        prev_log_term_index: prev_log_term_index,
        entries: entries,
        leader_commit_index: state.commit_index
      })
    end)
  end

  defp add_vote(state, voter) do
    state = put_in(state.election_state.votes, MapSet.put(state.election_state.votes, voter))

    if (state.cluster_config |> length |> div(2)) + 1 <= MapSet.size(state.election_state.votes),
      do: state |> convert_to_leader(),
      else: state
  end

  # TODO: Leader could be disposed if it cannot maintain a quorum.
  defp reset_timers(state) do
    Logger.info("#{inspect(state.id)}: Refreshing timers")

    if state.server_state == :candidate or state.server_state == :follower do
      state =
        put_in(
          state.election_state.timer,
          Timer.reset(state.election_state.timer, election_timeout())
        )

      put_in(state.heartbeat_timer, Timer.stop(state.heartbeat_timer))
    else
      state =
        put_in(state.heartbeat_timer, Timer.reset(state.heartbeat_timer, @heartbeat_timeout))

      put_in(state.election_state.timer, Timer.stop(state.election_state.timer))
    end
  end

  defp convert_to_candidate(state) do
    Logger.info("#{inspect(state.id)}: Converting to candidate")
    new_term_index = state.term_index + 1

    RPC.broadcast(
      %RPC.RequestVoteRequest{
        from: state.id,
        term_index: new_term_index,
        # TODO: This should change when we implement snapshotting and compaction.
        last_log_index: length(state.log),
        last_log_term_index: nil
      },
      neighbours(state)
    )

    %{
      state
      | term_index: new_term_index,
        voted_for: state.id,
        server_state: :candidate,
        next_index: %{},
        match_index: %{},
        election_state: %ElectionState{}
    }
    |> add_vote(state.id)
  end

  defp convert_to_follower(state, new_term_index) do
    Logger.info("#{inspect(state.id)}: Converting to follower")

    %{
      state
      | term_index: new_term_index,
        voted_for: nil,
        server_state: :follower,
        next_index: %{},
        match_index: %{},
        election_state: %ElectionState{}
    }
  end

  defp convert_to_leader(state) do
    Logger.info("#{inspect(state.id)}: Converting to leader")

    %{
      state
      | voted_for: nil,
        server_state: :leader,
        next_index: %{},
        match_index: %{},
        election_state: %ElectionState{}
    }
  end

  defp advance_log(state) do
    if state.commit_index > state.last_applied do
      entry_count = state.commit_index - state.last_applied
      {_head, tail} = Enum.split(state.log, state.last_applied)

      new_fsm =
        tail
        |> Enum.take(entry_count)
        |> Enum.reduce(state.fsm, fn entry ->
          state.fsm_module.execute(state.fsm, entry.command)
        end)

      Logger.info(
        "#{inspect(state.id)}: Applied #{state.last_applied + 1} to #{state.commit_index}"
      )

      %{state | last_applied: state.commit_index}
    else
      state
    end
  end

  defp neighbours(state) do
    state.cluster_config |> Enum.reject(fn id -> id == state.id end)
  end

  defp election_timeout() do
    :random.uniform(@election_timeout_high - @election_timeout_low + 1) - 1 +
      @election_timeout_low
  end

  defp merge_logs([], new), do: new

  defp merge_logs(old, []), do: old

  defp merge_logs([old_head | old_tail], [new_head, new_tail] = tail) do
    if old_head.term_index != new_head.term_index do
      tail
    else
      old_head ++ merge_logs(old_tail, new_tail)
    end
  end

  # TOOO: This should change when we implement snapshotting and compaction.
  defp split_log(log, index) do
    {head, tail} = Enum.split(log, index)
    {length(head), if(head == [], do: nil, else: tl(head).term_index), tail}
  end
end
