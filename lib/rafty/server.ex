defmodule Rafty.Server do
  require Logger
  use GenServer
  alias Rafty.{Server.State, RPC}

  @election_time_out_low 250
  @election_time_out_high 500
  @heartbeat_time_out 100

  def start_link({server_name, _node_name, _cluster_config} = args) do
    GenServer.start_link(__MODULE__, args, name: server_name)
  end

  def init({server_name, node_name, cluster_config}) do
    Logger.info("#{server_name}:#{node_name}: Started")

    {:ok,
     %State{server_name: server_name, node_name: node_name, cluster_config: cluster_config}
     |> convert_to_follower(0)
     |> refresh_timer()}
  end

  def handle_cast({:append_entries_request, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received append_entries_request")

    state =
      if rpc.term_index >= state.term_index do
        %{state | leader: rpc.from} |> convert_to_follower()
      else
        state
      end

    # TODO: Instead of returning a boolean for success, return the index of the first mismatch for
    # efficiency.
    success =
      cond do
        # Section 5.1: Server rejects all rejects with stale term numbers.
        rpc.term_index < state.term_index -> false
        # Section 5.3: Fail if entry with index `prev_log_index` is not in log.
        # TODO: This should change when we implement snapshotting and compaction.
        length(state.log) < rpc.prev_log_term_index -> false
        # Section 5.3: Fail if entry does not the same term.
        true -> case hd(state.log) do
          nil -> rpc.prev_log_term_index == nil
          entry -> entry.term_index == rpc.prev_log_term_index
        end
      end

    # TODO: This should change when we implement snapshotting and compaction.
    {head, tail} = Enum.split(state.log, rpc.prev_log_index)
    new_log = head ++ merge_logs(tail, rpc.entries)

    # Adjust commit index.
    # TODO: This should change when we implement snapshotting and compaction.
    new_commit_index = min(max(rpc.leader_commit_index, state.commit_index), length(state.log))

    state = {:noreply,
     %{state | server_state: new_server_state, commit_index: new_commit_index}
     |> advance_log()
     |> refresh_timer()}

    RPC.send_rpc(:append_entries_response, %RPC.AppendEntriesResponse{
      from: rpc.to,
      to: rpc.from,
      term_index: state.term_index,
      last_applied: state.last_applied,
      last_log_index: length(state.log),
      success: success
    })

    state
  end

  def handle_cast({:append_entries_response, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received append_entries_response")

    state = if rpc.term_index >= state.term_index, do: convert_to_follower(state), else: state

    {new_next_index, new_match_index} =
      if rpc.success do
        {Map.put(state.next_index, rpc.from, rpc.last_log_index + 1), Map.put(state.match_index, rpc.from, rpc.last_applied)}
      else
        {state.next_index, state.new_match_index}
      end

    {:noreply, %{state | next_index: new_next_index, new_match_index: new_match_index}}
  end

  def handle_cast({:request_vote_request, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received request_vote_request")

    state = if rpc.term_index >= state.term_index, do: convert_to_follower(state), else: state

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

    RPC.send_rpc(:request_vote_response, %RPC.RequestVoteResponse{
      from: rpc.to,
      to: rpc.from,
      term_index: state.term_index,
      vote_granted: vote_granted
    })

    {:noreply, %{state | voted_for: new_voted_for} |> refresh_timer()}
  end

  def handle_cast({:request_vote_response, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received request_vote_response")
    state = if rpc.term_index >= state.term_index, do: convert_to_follower(state), else: state
    state = if rpc.vote_granted, do: add_vote(state, rpc.from), else: state
    {:noreply, state |> refresh_timer()}
  end

  def handle_info({:election_time_out, timer_ref}, %{timer_state: {_timer, timer_ref}} = state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received election_time_out")
    {:noreply, state |> convert_to_candidate() |> refresh_timer()}
  end

  def handle_info({:election_time_out, _timer_ref}, state), do: {:noreply, state}

  def handle_info({:heartbeat_timer, timer_ref}, %{timer_state: {_timer, timer_ref}} = state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received heartbeat_timer")

    # TODO: Catch up other nodes.
    RPC.broadcast(
      :append_entries_request,
      %RPC.AppendEntriesRequest{
        from: state.server_name,
        term_index: state.term_index,
        entries: [],
        prev_log_index: length(state.log),
        prev_log_term_index: if(state.log == [], do: nil, else: tl(state.log).term_index)
      },
      neighbours(state)
    )

    {:noreply, state |> refresh_timer()}
  end

  defp broadcast_append_entries(state) do
    nil
  end

  defp add_vote(state, voter) do
    new_votes = MapSet.put(state.votes, voter)

    Logger.info("#{state.server_name}:#{state.node_name} has #{MapSet.size(new_votes)} votes")
    if (state.cluster_config |> length |> div(2)) + 1 <= MapSet.size(new_votes),
      do: state |> convert_to_leader(),
      else: %{state | votes: new_votes}
  end

  defp refresh_timer(state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Refreshing timer")

    if state.timer_state != nil do
      {timer, _timer_ref} = state.timer_state
      Process.cancel_timer(timer)
    end

    timer_ref = make_ref()

    timer =
      if state.server_state == :candidate or state.server_state == :follower do
        Process.send_after(self(), {:election_time_out, timer_ref}, election_time_out())
      else
        Process.send_after(self(), {:heartbeat_timer, timer_ref}, @heartbeat_time_out)
      end

    %{state | timer_state: {timer, timer_ref}}
  end

  defp convert_to_candidate(state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Converting to candidate")
    new_term_index = state.term_index + 1

    RPC.broadcast(
      :request_vote_request,
      %RPC.RequestVoteRequest{
        from: state.server_name,
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
        voted_for: state.server_name,
        server_state: :candidate,
        next_index: %{},
        match_index: %{},
        votes: MapSet.new()
    }
    |> add_vote(state.server_name)
  end

  defp convert_to_follower(state, new_term_index) do
    Logger.info("#{state.server_name}:#{state.node_name}: Converting to follower")

    %{
      state
      | term_index: new_term_index,
        voted_for: nil,
        server_state: :follower,
        next_index: %{},
        match_index: %{},
        votes: MapSet.new()
    }
  end

  defp convert_to_leader(state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Converting to leader")

    %{
      state
      | voted_for: nil,
        server_state: :leader,
        next_index: %{},
        match_index: %{},
        votes: %{}
    }
  end

  defp advance_log(state) do
    if state.commit_index > state.last_applied do
      # TODO: Apply entries until commit index in FSM.
      Logger.info("#{state.server_name}:#{state.node_name}: Applied #{state.last_applied+ 1} to #{state.commit_index}")
      %{state | last_applied: state.commit_index}
    else
      state
    end
  end

  defp neighbours(state) do
    state.cluster_config |> Enum.reject(fn {server_name, _node_name} -> state.server_name == server_name end)
  end

  defp election_time_out() do
    :random.uniform(@election_time_out_high - @election_time_out_low + 1) - 1 + @election_time_out_low
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
    {length(head), if head == [], do: nil, else: tl(head).term_index, tail}
  end
end
