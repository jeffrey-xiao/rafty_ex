defmodule Rafty.Server do
  require Logger
  use GenServer
  alias Rafty.{Server.State, RPC}

  # TODO: Convert to functions that uses randomization.
  @election_time_out 250
  @heartbeat_interval 100

  def start_link({server_name, _node_name} = args) do
    GenServer.start_link(__MODULE__, args, name: server_name(server_name))
  end

  def server_name(server_name) do
    :"Server#{server_name}"
  end

  def init({server_name, node_name}) do
    Logger.info("#{server_name}:#{node_name}: Started")
    {:ok, %State{server_name: server_name, node_name: node_name} |> convert_to_follower(0) |> refresh_timer()}
  end

  def append_entries(server_name, node_name, rpc) do
    GenServer.cast({server_name, node_name}, {:append_entries, rpc})
  end

  def append_entries_reply(server_name, node_name, rpc) do
    GenServer.cast({server_name, node_name}, {:append_entries_reply, rpc})
  end

  def request_vote({server_name, node_name}, rpc) do
    GenServer.cast({server_name, node_name}, {:request_vote, rpc})
  end

  def request_vote_reply({server_name, node_name}, rpc) do
    GenServer.cast({server_name, node_name}, {:request_vote_reply, rpc})
  end

  # Section 5.1: Convert to follower if request or response term index is greater than state term
  # index.
  def handle_cast({_, %{term_index: rpc_term_index}}, %{term_index: state_term_index} = state)
      when rpc_term_index > state_term_index do
    {:noreply, state |> convert_to_follower(rpc_term_index) |> refresh_timer()}
  end

  def handle_cast({:append_entries, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received append_entries")
    # TODO: Instead of returning a boolean for success, return the index of the first mismatch for
    # efficiency.
    success =
      cond do
        # Section 5.1: Server rejects all rejects with stale term numbers.
        rpc.term_index < state.term_index -> false
        # Section 5.3: Fail if entry with index `prev_log_index` is not in log.
        # TODO: Do proper check instead of using length
        length(state.log) < rpc.prev_log_term_index -> false
      end

    # Convert to follower.
    new_server_state = if rpc.term_index >= state.term_index, do: :follower, else: state.state

    # TODO: Add entries and truncate to log.

    # Adjust commit index.
    last_entry = List.last(rpc.entries)

    new_commit_index =
      if rpc.leader_commit_index > state.commit_index && last_entry != nil do
        min(rpc.leader_commit_index, last_entry)
      else
        state.commit_index
      end

    RPC.send_rpc(:append_entries_response, %RPC.AppendEntriesResponse{
      from: rpc.to,
      to: rpc.from,
      term_index: state.term_index,
      success: success
    })

    {:noreply,
     %{state | server_state: new_server_state, commit_index: new_commit_index}
     |> advance_log()
     |> refresh_timer()}
  end

  # TODO: Handle out-of-sync nodes.
  # TODO: Refresh heartbeat RPCs.
  def handle_cast({:append_entries_reply, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received append_entries_reply")
    {:noreply, state}
  end

  def handle_cast({:request_vote, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received request_vote")
    vote_granted =
      cond do
        # Section 5.1: Server rejects all requests with stale term numbers.
        rpc.term_index < state.term_index -> false
        # Candidate has already voted.
        state.voted_for != nil and state.voted_for != rpc.from -> false
        # Section 5.4.1: Candidate log must be be at least up-to-date as current log.
        state.term_index > rpc.last_log_term_index -> false
        # TODO: Add struct for log entry and check for index instead of length.
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

  def handle_cast({:request_vote_reply, rpc}, state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received request_vote_reply")
    new_state = if rpc.vote_granted, do: add_vote(state, rpc.from), else: state
    {:noreply, new_state |> refresh_timer()}
  end

  def handle_info({:election_time_out, timer_ref}, %{timer_state: {_timer, timer_ref}} = state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received election_time_out")
    {:noreply, state |> convert_to_candidate() |> refresh_timer()}
  end

  def handle_info({:election_time_out, _timer_ref}, state), do: {:noreply, state}

  def handle_info({:heartbeat_timer, timer_ref}, %{timer_state: {_timer, timer_ref}} = state) do
    Logger.info("#{state.server_name}:#{state.node_name}: Received heartbeat_timer")
    RPC.broadcast(
      :append_entries_request,
      %RPC.AppendEntriesRequest{
        from: state.server_name,
        term_index: state.term_index,
        prev_log_index: length(state.log),
        prev_log_term_index: if(state.log == [], do: nil, else: tl(state.log).term_index)
      },
      state.neighbours
    )

    {:noreply, state |> refresh_timer()}
  end

  defp add_vote(state, voter) do
    new_votes = MapSet.put(state.votes, voter)
    if (state.neighbours |> length |> div(2)) + 1 <= MapSet.size(new_votes),
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
        Process.send_after(self(), {:election_time_out, timer_ref}, @election_time_out)
      else
        Process.send_after(self(), {:heartbeat_timer, timer_ref}, @heartbeat_interval)
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
        # TODO: Properly handle last log index.
        last_log_index: length(state.log),
        last_log_term_index: nil
      },
      state.neighbours
    )

    %{
      state
      | term_index: new_term_index,
        voted_for: state.server_name,
        server_state: :candidate,
        next_index: %{},
        match_index: %{},
        votes: MapSet.new()
    } |> add_vote(state.server_name)
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
      %{state | last_applied: state.commit_index}
    else
      state
    end
  end
end
