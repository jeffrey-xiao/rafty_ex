defmodule Rafty.Server do
  require Logger
  use GenServer
  alias Rafty.{Log, RPC, Server.State, Timer}

  @election_timeout_low 250
  @election_timeout_high 500
  @heartbeat_timeout 100

  def start_link({server_name, _node_name, _cluster_config, _fsm, _log} = args) do
    GenServer.start_link(__MODULE__, args, name: server_name)
  end

  @impl GenServer
  def init({server_name, node_name, cluster_config, fsm, _log}) do
    Logger.info("#{inspect({server_name, node_name})}: Started")
    :random.seed(:erlang.now())

    {:ok,
     %State{
       id: {server_name, node_name},
       cluster_config: cluster_config,
       fsm: fsm,
       fsm_state: fsm.init()
     }
     |> convert_to_follower()
     |> reset_election_timer()}
  end

  @impl GenServer
  def handle_call(:execute, from, state) do
    {:reply, nil, state}
  end

  @impl GenServer
  def handle_call(:query, from, state) do
    {:reply, nil, state}
  end

  @impl GenServer
  def handle_call(:status, _from, state) do
    {:reply,
     {state.server_state, Log.Server.get_term_index(state.id), state.commit_index,
      state.last_applied}, state}
  end

  # TODO: Have a queue of clients waiting to hear from leaders.
  @impl GenServer
  def handle_call(:leader, from, state) do
    if state.leader != nil,
      do: {:reply, state.leader, state},
      else: {:noreply, %{state | leader_requests: [from | state.leader_requests]}}
  end

  @impl GenServer
  def handle_call(%RPC.AppendEntriesRequest{} = rpc, _from, state) do
    Logger.info("#{inspect(state.id)}: Received append_entries_request")

    term_index = Log.Server.get_term_index(state.id)

    {state, term_index} =
      if rpc.term_index >= term_index do
        Enum.each(state.leader_requests, fn client -> GenServer.reply(client, rpc.from) end)
        Log.Server.set_term_index(state.id, rpc.term_index)

        {%{state | leader: rpc.from, leader_requests: []} |> convert_to_follower(),
         rpc.term_index}
      else
        {state, term_index}
      end

    # TODO: Instead of returning a boolean for success, return the index of the log entry with the
    # same term index as the mismatch for efficiency.
    log_length = Log.Server.length(state.id)

    success =
      cond do
        # Section 5.1: Server rejects all rejects with stale term numbers.
        rpc.term_index < term_index ->
          false

        # Section 5.3: Fail if entry with index `prev_log_index` is not in log.
        # TODO: This should change when we implement snapshotting and compaction.
        log_length < rpc.prev_log_index ->
          false

        # Section 5.3: Fail if entry does not the same term.
        true ->
          case Log.Server.get_entry(state.id, log_length) do
            nil -> rpc.prev_log_term_index == nil
            entry -> entry.term_index == rpc.prev_log_term_index
          end
      end

    # TODO: This should change when we implement snapshotting and compaction.
    new_commit_index =
      if success do
        # TODO: This should change when we implement snapshotting and compaction.
        if rpc.entries != [] do
          Log.Server.append_entries(state.id, rpc.entries, rpc.prev_log_index)
        end

        min(max(rpc.leader_commit_index, state.commit_index), Log.Server.length(state.id))
      else
        state.commit_index
      end

    state =
      %{state | commit_index: new_commit_index}
      |> advance_log()
      |> reset_election_timer()

    {:reply,
     %RPC.AppendEntriesResponse{
       from: rpc.to,
       to: rpc.from,
       term_index: term_index,
       last_applied: state.last_applied,
       last_log_index: log_length,
       success: success
     }, state}
  end

  @impl GenServer
  def handle_call(%RPC.RequestVoteRequest{} = rpc, _from, state) do
    Logger.info("#{inspect(state.id)}: Received request_vote_request")

    term_index = Log.Server.get_term_index(state.id)

    {state, term_index} =
      if rpc.term_index > term_index do
        Log.Server.set_term_index(state.id, rpc.term_index)
        {convert_to_follower(state), rpc.term_index}
      else
        {state, term_index}
      end

    log_length = Log.Server.length(state.id)
    last_entry = Log.Server.get_entry(state.id, log_length)
    voted_for = Log.Server.get_voted_for(state.id)

    vote_granted =
      cond do
        # Section 5.1: Server rejects all requests with stale term numbers.
        rpc.term_index < term_index ->
          false

        # Candidate has already voted.
        voted_for != nil and voted_for != rpc.from ->
          false

        # Section 5.4.1: Candidate log must be be at least up-to-date as current log.
        last_entry == nil ->
          true

        last_entry.term_index > rpc.last_log_term_index ->
          false

        # TODO: This should change when we implement snapshotting and compaction.
        Log.Server.length(state.id) > rpc.last_log_index ->
          false

        true ->
          true
      end

    if vote_granted do
      Log.Server.set_voted_for(state.id, rpc.from)
    end

    {:reply,
     %RPC.RequestVoteResponse{
       from: rpc.to,
       to: rpc.from,
       term_index: term_index,
       vote_granted: vote_granted
     }, state |> reset_election_timer()}
  end

  @impl GenServer
  def handle_cast(%RPC.AppendEntriesResponse{} = rpc, state) do
    Logger.info("#{inspect(state.id)}: Received append_entries_response")

    term_index = Log.Server.get_term_index(state.id)

    {state, term_index} =
      if rpc.term_index > term_index do
        Log.Server.set_term_index(state.id, rpc.term_index)
        {convert_to_follower(state), rpc.term_index}
      else
        {state, term_index}
      end

    {new_next_index, new_match_index} =
      if rpc.success,
        do:
          {Map.put(state.next_index, rpc.from, rpc.last_log_index + 1),
           Map.put(state.match_index, rpc.from, rpc.last_applied)},
        else:
          {Map.update!(state.next_index, rpc.from, fn next_index -> next_index - 1 end),
           state.match_index}

    {:noreply, %{state | next_index: new_next_index, match_index: new_match_index}}
  end

  @impl GenServer
  def handle_cast(%RPC.RequestVoteResponse{} = rpc, state) do
    Logger.info("#{inspect(state.id)}: Received request_vote_response")

    term_index = Log.Server.get_term_index(state.id)

    {state, term_index} =
      if rpc.term_index > term_index do
        Log.Server.set_term_index(state.id, rpc.term_index)
        {convert_to_follower(state), rpc.term_index}
      else
        {state, term_index}
      end

    state = if rpc.vote_granted, do: add_vote(state, rpc.from), else: state
    {:noreply, state |> reset_election_timer()}
  end

  @impl GenServer
  def handle_info({:election_timeout, _ref}, %{server_state: :leader} = state),
    do: {:noreply, state}

  @impl GenServer
  def handle_info({:election_timeout, ref}, %{election_timer: %{ref: ref}} = state) do
    Logger.info("#{inspect(state.id)}: Received election_timeout")
    {:noreply, state |> convert_to_candidate() |> reset_election_timer()}
  end

  @impl GenServer
  def handle_info({:election_timeout, _ref}, state), do: {:noreply, state}

  # TODO: Dispose of leader if it cannot maintain quorum.
  @impl GenServer
  def handle_info(
        {:heartbeat_timeout, ref},
        %{heartbeat_timer: %{ref: ref}, server_state: :leader} = state
      ) do
    Logger.info("#{inspect(state.id)}: Received heartbeat_timer")
    broadcast_append_entries(state)
    {:noreply, state |> reset_heartbeat_timer()}
  end

  @impl GenServer
  def handle_info({:heartbeat_timeout, _ref}, state), do: {:noreply, state}

  defp broadcast_append_entries(state) do
    state
    |> neighbours()
    |> Enum.each(fn neighbour ->
      prev_log_index = state.next_index[neighbour] - 1

      prev_log_term_index =
        if prev_log_index == 0,
          do: nil,
          else: Log.Server.get_entry(state.id, prev_log_index).term_index

      entries = Log.Server.get_tail(state.id, state.next_index[neighbour])

      RPC.send_rpc(%RPC.AppendEntriesRequest{
        from: state.id,
        to: neighbour,
        term_index: Log.Server.get_term_index(state.id),
        prev_log_index: prev_log_index,
        prev_log_term_index: prev_log_term_index,
        entries: entries,
        leader_commit_index: state.commit_index
      })
    end)
  end

  defp add_vote(%{server_state: :candidate} = state, voter) do
    state = put_in(state.votes, MapSet.put(state.votes, voter))

    if (state.cluster_config |> length |> div(2)) + 1 <= MapSet.size(state.votes),
      do: state |> convert_to_leader(),
      else: state
  end

  defp add_vote(state, _voter), do: state

  defp reset_election_timer(%{server_state: :leader} = state), do: state

  defp reset_election_timer(state) do
    Logger.info("#{inspect(state.id)}: Refreshing election timer")

    put_in(
      state.election_timer,
      Timer.reset(state.election_timer, election_timeout())
    )
  end

  # TODO: Leader could be disposed if it cannot maintain a quorum.
  defp reset_heartbeat_timer(%{server_state: :leader} = state) do
    Logger.info("#{inspect(state.id)}: Refreshing heartbeat timer")
    put_in(state.heartbeat_timer, Timer.reset(state.heartbeat_timer, @heartbeat_timeout))
  end

  defp reset_heartbeat_timer(state), do: state

  defp convert_to_candidate(state) do
    Logger.info("#{inspect(state.id)}: Converting to candidate")

    term_index = Log.Server.increment_term_index(state.id)
    # TODO: This should change when we implement snapshotting and compaction.
    last_log_index = Log.Server.length(state.id)

    last_log_term_index =
      if last_log_index == 0,
        do: nil,
        else: Log.Server.get_entry(state.id, last_log_index).term_index

    RPC.broadcast(
      %RPC.RequestVoteRequest{
        from: state.id,
        term_index: term_index,
        last_log_index: last_log_index,
        last_log_term_index: last_log_term_index
      },
      neighbours(state)
    )

    Log.Server.set_voted_for(state.id, state.id)

    %{
      state
      | server_state: :candidate,
        leader: nil,
        next_index: nil,
        match_index: nil,
        votes: MapSet.new()
    }
    |> add_vote(state.id)
  end

  defp convert_to_follower(state) do
    Logger.info("#{inspect(state.id)}: Converting to follower")
    Log.Server.set_voted_for(state.id, nil)

    %{
      state
      | server_state: :follower,
        next_index: nil,
        match_index: nil,
        votes: MapSet.new()
    }
  end

  defp convert_to_leader(state) do
    Logger.info("#{inspect(state.id)}: Converting to leader")

    log_length = Log.Server.length(state.id)
    Log.Server.set_voted_for(state.id, state.id)

    %{
      state
      | server_state: :leader,
        leader: state.id,
        next_index:
          state.cluster_config |> Enum.map(fn id -> {id, log_length + 1} end) |> Enum.into(%{}),
        match_index: state.cluster_config |> Enum.map(fn id -> {id, 0} end) |> Enum.into(%{}),
        votes: MapSet.new()
    }
    |> reset_heartbeat_timer()
  end

  defp advance_log(state) do
    if state.commit_index > state.last_applied do
      entry_count = state.commit_index - state.last_applied

      new_fsm_state =
        state.id
        |> Log.Server.get_tail(state.last_applied)
        |> Enum.take(entry_count)
        |> Enum.reduce(state.fsm_state, fn acc, entry ->
          state.fsm.execute(acc, entry.command)
        end)

      Logger.info(
        "#{inspect(state.id)}: Applied #{state.last_applied + 1} to #{state.commit_index}"
      )

      %{state | last_applied: state.commit_index, fsm_state: new_fsm_state}
    else
      state
    end
  end

  defp neighbours(state) do
    state.cluster_config |> Enum.reject(fn id -> id == state.id end)
  end

  defp election_timeout do
    :random.uniform(@election_timeout_high - @election_timeout_low + 1) - 1 +
      @election_timeout_low
  end
end
