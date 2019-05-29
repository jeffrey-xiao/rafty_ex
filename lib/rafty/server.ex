defmodule Rafty.Server do
  use GenServer
  alias Rafty.{Server.State, RPC}

  def start_link({server_name, _node_name} = args) do
    GenServer.start_link(__MODULE__, args, name: server_name(server_name))
  end

  def server_name(server_name) do
    :"Server#{server_name}"
  end

  def init({server_name, node_name}) do
    {:ok, %State{server_name: server_name, node_name: node_name}}
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
    {:noreply, state |> convert_to_follower(rpc_term_index)}
  end

  def handle_cast({:append_entries, rpc}, state) do
    # TODO: Instead of returning a boolean for success, return the index of the first mismatch for
    # efficiency.
    success =
      cond do
        # Section 5.1: Server rejects all rejects with stale term numbers.
        rpc.term_index < state.current_term_index -> false
        # Section 5.3: Fail if entry with index `prev_log_index` is not in log.
        # TODO: Do proper check instead of using length
        length(state.log) < rpc.prev_log_term_index -> false
      end

    # Convert to follower.
    new_server_state =
      if rpc.term_index >= state.current_term_index, do: :follower, else: state.state

    # TODO: Add entries and truncate to log.

    # Adjust commit index.
    last_entry = List.last(rpc.entries)

    new_commit_index =
      if rpc.leader_commit_index > state.commit_index && last_entry != nil do
        min(rpc.leader_commit_index, last_entry)
      else
        state.commit_index
      end

    RPC.send_rpc(%RPC.AppendEntriesResponse{
      from: rpc.to,
      to: rpc.from,
      term_index: state.current_term_index,
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
    nil
  end

  def handle_cast({:request_vote, rpc}, state) do
    vote_granted =
      cond do
        # Section 5.1: Server rejects all requests with stale term numbers.
        rpc.term_index < state.current_term_index -> false
        # Candidate has already voted.
        state.voted_for != nil and state.voted_for != rpc.from -> false
        # Section 5.4.1: Candidate log must be be at least up-to-date as current log.
        state.current_term_index > rpc.last_log_term_index -> false
        # TODO: Add struct for log entry and check for index instead of length.
        length(state.log) > rpc.last_log_index -> false
        true -> true
      end

    RPC.send_rpc(%RPC.RequestVoteResponse{
      from: rpc.to,
      to: rpc.from,
      term_index: state.current_term_index,
      vote_granted: vote_granted
    })

    {:noreply, state |> refresh_timer()}
  end

  def handle_cast({:request_vote_reply, rpc}, state) do
    new_votes = if rpc.vote_granted, do: MapSet.put(state.votes, rpc.from), else: state.votes

    new_server_state =
      if (state.neighbours |> length |> div(2)) + 1 <= length(new_votes),
        do: :leader,
        else: state.server_state

    {:noreply, %{state | server_state: new_server_state, votes: new_votes} |> refresh_timer()}
  end

  def handle_info({:election_time_out, timer_ref}, %{timer_state: {timer, timer_ref}} = state) do
    {:noreply, state |> convert_to_candidate()}
  end

  def handle_info({:election_time_out, _timer_ref}, state), do: {:noreply, state}

  defp refresh_timer(state) do
    if state.timer_state != nil do
      {timer, _timer_ref} = state.timer_state
      Process.cancel_timer(timer)
    end

    new_timer_state =
      if state.server_state == :candidate or state.server_state == :follower do
        timer_ref = make_ref()
        timer = Process.send_after(self(), {:election_time_out, timer_ref}, @election_time_out)
      else
        nil
      end

    %{state | timer_state: new_timer_state}
  end

  defp convert_to_candidate(state) do
    new_state =
      %{
        state
        | current_term_index: state.current_term_index + 1,
          voted_for: state.server_name,
          server_state: :candidate,
          next_index: %{},
          match_index: %{},
          votes: MapSet.new([state.server_name])
      }
      |> refresh_timer()

    RPC.broadcast(:request_vote_request, %RPC.RequestVoteRequest{
      from: state.server_name,
      term_index: state.current_term_index,
      last_log_index: length(state.log),
      last_log_term_index: nil
    })
  end

  defp convert_to_follower(state, new_term_index) do
    new_state =
      %{
        state
        | current_term_index: new_term_index,
          voted_for: nil,
          server_state: :follower,
          next_index: %{},
          match_index: %{},
          votes: MapSet.new()
      }
      |> refresh_timer()
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
