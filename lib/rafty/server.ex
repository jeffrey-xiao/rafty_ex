defmodule Rafty.Server do
  require Logger
  use GenServer
  alias Rafty.{Log, FSM, RPC, Timer}

  @election_timeout_low 250
  @election_timeout_high 500
  @heartbeat_timeout 100

  @type t :: %__MODULE__{
          id: Rafty.id(),
          server_state: Rafty.server_state(),
          cluster_config: [Rafty.id()],
          leader: Rafty.id() | nil,
          commit_index: Rafty.log_index(),
          last_applied: Rafty.log_index(),
          next_index: %{atom() => Rafty.log_index()},
          match_index: %{atom() => Rafty.log_index()},
          heartbeat_timer: Timer.t(),
          votes: MapSet.t(Rafty.id()),
          election_timer: Timer.t(),
          leader_requests: [GenServer.from()],
          requests: [{GenServer.from(), Rafty.log_index()}]
        }
  defstruct id: nil,
            server_state: :follower,
            cluster_config: [],
            leader: nil,
            commit_index: 0,
            last_applied: 0,
            # Leader specific state.
            next_index: %{},
            match_index: %{},
            heartbeat_timer: Timer.new(:heartbeat_timeout),
            # Election specific state.
            votes: MapSet.new(),
            election_timer: Timer.new(:election_timeout),
            # Client requests
            leader_requests: [],
            requests: []

  @spec start_link(Rafty.args()) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: args[:server_name])
  end

  @impl GenServer
  def init(args) do
    Logger.info("#{inspect({args[:server_name], args[:node_name]})}: Started")
    :random.seed(:erlang.now())

    {:ok,
     %__MODULE__{
       id: {args[:server_name], args[:node_name]},
       cluster_config: args[:cluster_config]
     }
     |> convert_to_follower()
     |> reset_election_timer()}
  end

  @impl GenServer
  def handle_call(:register, from, %__MODULE__{server_state: :leader} = state) do
    term_index = Log.Server.get_term_index(state.id)
    log_index = Log.Server.length(state.id)

    Log.Server.append_entries(
      state.id,
      [
        %Log.Entry{
          timestamp: :erlang.monotonic_time(:nanosecond),
          term_index: term_index,
          command: :register,
          payload: nil
        }
      ],
      log_index
    )

    broadcast_append_entries(state)

    {:noreply,
     %__MODULE__{
       state
       | requests: [{from, log_index + 1} | state.requests],
         match_index: Map.put(state.match_index, state.id, log_index + 1)
     }
     |> advance_commit()}
  end

  @impl GenServer
  def handle_call(
        {:execute, client_id, ref, payload},
        from,
        %__MODULE__{server_state: :leader} = state
      ) do
    term_index = Log.Server.get_term_index(state.id)
    log_index = Log.Server.length(state.id)

    Log.Server.append_entries(
      state.id,
      [
        %Log.Entry{
          client_id: client_id,
          ref: ref,
          timestamp: :erlang.monotonic_time(:nanosecond),
          term_index: term_index,
          command: :execute,
          payload: payload
        }
      ],
      log_index
    )

    broadcast_append_entries(state)

    {:noreply,
     %__MODULE__{
       state
       | requests: [{from, log_index + 1} | state.requests],
         match_index: Map.put(state.match_index, state.id, log_index + 1)
     }
     |> advance_commit()}
  end

  @impl GenServer
  def handle_call({:execute, _payload}, from, state),
    do: {:reply, {:not_leader, state.leader}}

  @impl GenServer
  def handle_call({:query, _payload}, from, %__MODULE__{server_state: :leader} = state) do
    {:reply, nil, state}
  end

  @impl GenServer
  def handle_call({:query, _payload}, from, state),
    do: {:reply, {:not_leader, state.leader}}

  @impl GenServer
  def handle_call(:status, _from, state) do
    {:reply,
     {state.server_state, Log.Server.get_term_index(state.id), state.commit_index,
      state.last_applied}, state}
  end

  @impl GenServer
  def handle_call(:leader, from, state) do
    if state.leader != nil,
      do: {:reply, state.leader, state},
      else: {:noreply, %__MODULE__{state | leader_requests: [from | state.leader_requests]}}
  end

  @impl GenServer
  def handle_call(%RPC.AppendEntriesRequest{} = rpc, _from, state) do
    Logger.info("#{inspect(state.id)}: Received append_entries_request: #{inspect(rpc)}")

    term_index = Log.Server.get_term_index(state.id)

    {state, term_index} =
      if rpc.term_index >= term_index do
        Enum.each(state.leader_requests, fn client -> GenServer.reply(client, rpc.from) end)
        Log.Server.set_term_index(state.id, rpc.term_index)

        state = convert_to_follower(state)
        {%__MODULE__{state | leader: rpc.from, leader_requests: []}, rpc.term_index}
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
          case Log.Server.get_entry(state.id, rpc.prev_log_index) do
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
      %__MODULE__{state | commit_index: new_commit_index}
      |> advance_applied()
      |> reset_election_timer()

    {:reply,
     %RPC.AppendEntriesResponse{
       from: rpc.to,
       to: rpc.from,
       term_index: term_index,
       last_log_index: Log.Server.length(state.id),
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
    Logger.info("#{inspect(state.id)}: Received append_entries_response: #{inspect(rpc)}")

    term_index = Log.Server.get_term_index(state.id)

    {state, _term_index} =
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
           Map.put(state.match_index, rpc.from, rpc.last_log_index)},
        else:
          {Map.update!(state.next_index, rpc.from, fn next_index -> next_index - 1 end),
           state.match_index}

    {:noreply,
     %__MODULE__{state | next_index: new_next_index, match_index: new_match_index}
     |> advance_commit()
     |> advance_applied()}
  end

  @impl GenServer
  def handle_cast(%RPC.RequestVoteResponse{} = rpc, state) do
    Logger.info("#{inspect(state.id)}: Received request_vote_response")

    term_index = Log.Server.get_term_index(state.id)

    {state, _term_index} =
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
  def handle_info({:election_timeout, _ref}, %__MODULE__{server_state: :leader} = state),
    do: {:noreply, state}

  @impl GenServer
  def handle_info({:election_timeout, ref}, %__MODULE__{election_timer: %Timer{ref: ref}} = state) do
    Logger.info("#{inspect(state.id)}: Received election_timeout")
    {:noreply, state |> convert_to_candidate() |> reset_election_timer()}
  end

  @impl GenServer
  def handle_info({:election_timeout, _ref}, state), do: {:noreply, state}

  # TODO: Dispose of leader if it cannot maintain quorum.
  @impl GenServer
  def handle_info(
        {:heartbeat_timeout, ref},
        %__MODULE__{heartbeat_timer: %Timer{ref: ref}, server_state: :leader} = state
      ) do
    Logger.info("#{inspect(state.id)}: Received heartbeat_timer")
    broadcast_append_entries(state)
    {:noreply, state |> reset_heartbeat_timer()}
  end

  @impl GenServer
  def handle_info({:heartbeat_timeout, _ref}, state), do: {:noreply, state}

  @spec neighbours(t()) :: [Rafty.id()]
  defp neighbours(state) do
    state.cluster_config |> Enum.reject(fn id -> id == state.id end)
  end

  @spec reset_election_timer(t()) :: t()
  defp reset_election_timer(%__MODULE__{server_state: :leader} = state), do: state

  defp reset_election_timer(state) do
    Logger.info("#{inspect(state.id)}: Refreshing election timer")

    put_in(
      state.election_timer,
      Timer.reset(state.election_timer, election_timeout())
    )
  end

  # TODO: Leader could be disposed if it cannot maintain a quorum.
  @spec reset_heartbeat_timer(t()) :: t()
  defp reset_heartbeat_timer(%__MODULE__{server_state: :leader} = state) do
    Logger.info("#{inspect(state.id)}: Refreshing heartbeat timer")
    put_in(state.heartbeat_timer, Timer.reset(state.heartbeat_timer, @heartbeat_timeout))
  end

  @spec convert_to_candidate(t()) :: t()
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

    %__MODULE__{
      state
      | server_state: :candidate,
        leader: nil,
        next_index: %{},
        match_index: %{},
        votes: MapSet.new()
    }
    |> add_vote(state.id)
  end

  @spec convert_to_follower(t()) :: t()
  defp convert_to_follower(state) do
    Logger.info("#{inspect(state.id)}: Converting to follower")
    Log.Server.set_voted_for(state.id, nil)

    %__MODULE__{
      state
      | server_state: :follower,
        leader: nil,
        next_index: %{},
        match_index: %{},
        votes: MapSet.new()
    }
  end

  @spec convert_to_leader(t()) :: t()
  defp convert_to_leader(state) do
    Logger.info("#{inspect(state.id)}: Converting to leader")

    Enum.each(state.leader_requests, fn client -> GenServer.reply(client, state.id) end)

    log_length = Log.Server.length(state.id)
    term_index = Log.Server.get_term_index(state.id)

    Log.Server.append_entries(
      state.id,
      [
        %Log.Entry{
          term_index: term_index,
          command: :no_op,
          payload: nil
        }
      ],
      log_length
    )

    Log.Server.set_voted_for(state.id, nil)

    %__MODULE__{
      state
      | server_state: :leader,
        leader: state.id,
        next_index:
          state.cluster_config |> Enum.map(fn id -> {id, log_length + 1} end) |> Enum.into(%{}),
        match_index: state.cluster_config |> Enum.map(fn id -> {id, 0} end) |> Enum.into(%{}),
        votes: MapSet.new(),
        leader_requests: [],
        requests: []
    }
    |> reset_heartbeat_timer()
  end

  @spec broadcast_append_entries(t()) :: :ok
  defp broadcast_append_entries(state) do
    state
    |> neighbours()
    |> Enum.each(fn neighbour ->
      prev_log_index = state.next_index[neighbour] - 1

      prev_log_term_index =
        if prev_log_index == 0,
          do: nil,
          else: Log.Server.get_entry(state.id, prev_log_index).term_index

      entries = Log.Server.get_entries(state.id, state.next_index[neighbour])

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

  @spec advance_commit(t()) :: t()
  defp advance_commit(state) do
    index = state.cluster_config |> length |> div(2)

    log_index =
      state.match_index
      |> Enum.map(fn {_id, index} -> index end)
      |> Enum.sort()
      |> Enum.at(index)

    entry = Log.Server.get_entry(state.id, log_index)
    term_index = Log.Server.get_term_index(state.id)

    commit_index =
      if entry != nil && entry.term_index == term_index,
        do: log_index,
        else: state.commit_index

    %__MODULE__{state | commit_index: commit_index}
  end

  @spec advance_applied(t()) :: t()
  defp advance_applied(state) do
    if state.commit_index > state.last_applied do
      entry_count = state.commit_index - state.last_applied

      requests =
        state.id
        |> Log.Server.get_entries(state.last_applied + 1)
        |> Enum.take(entry_count)
        |> Enum.with_index(state.last_applied + 1)
        |> Enum.reduce(state.requests, fn {entry, index}, requests ->
          resp =
            case entry.command do
              :execute ->
                FSM.Server.execute(
                  state.id,
                  entry.client_id,
                  entry.ref,
                  entry.timestamp,
                  entry.payload
                )

              :register ->
                FSM.Server.register(state.id, index, entry.timestamp)

              _ ->
                nil
            end

          respond_to_requests(requests, index, resp)
          requests
        end)

      Logger.info(
        "#{inspect(state.id)}: Applied #{state.last_applied + 1} to #{state.commit_index}"
      )

      %__MODULE__{
        state
        | last_applied: state.commit_index,
          requests: requests
      }
    else
      state
    end
  end

  @spec respond_to_requests(
          [{GenServer.from(), Rafty.log_index()}],
          Rafty.log_index(),
          term()
        ) :: [{GenServer.from(), Rafty.log_index()}]
  defp respond_to_requests([], _applied_log_index, _resp), do: []

  defp respond_to_requests([{from, log_index} | tail] = reqs, applied_log_index, resp) do
    cond do
      log_index < applied_log_index ->
        respond_to_requests(tail, applied_log_index, resp)

      log_index == applied_log_index ->
        GenServer.reply(from, resp)
        tail

      log_index > applied_log_index ->
        reqs
    end
  end

  @spec election_timeout :: non_neg_integer()
  defp election_timeout do
    :random.uniform(@election_timeout_high - @election_timeout_low + 1) - 1 +
      @election_timeout_low
  end

  @spec add_vote(t(), Rafty.id()) :: t()
  defp add_vote(%__MODULE__{server_state: :candidate} = state, voter) do
    state = put_in(state.votes, MapSet.put(state.votes, voter))

    if (state.cluster_config |> length |> div(2)) + 1 <= MapSet.size(state.votes),
      do: state |> convert_to_leader(),
      else: state
  end

  defp add_vote(state, _voter), do: state
end
