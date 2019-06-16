defmodule Rafty.FSM.Server do
  use GenServer

  @typep request_info :: {reference() | nil, term(), Rafty.timestamp()}
  @typep requests :: %{Rafty.term_index() => request_info()}
  @type t :: %__MODULE__{
          fsm: module(),
          fsm_state: term(),
          ttl: non_neg_integer(),
          requests: requests()
        }
  @enforce_keys [:fsm, :fsm_state, :ttl, :requests]
  defstruct [
    :fsm,
    :fsm_state,
    :ttl,
    :requests
  ]

  @spec start_link(Rafty.args()) :: {:ok, term()} | {:error, term()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: name(args[:server_name]))
  end

  @spec name(Rafty.server_name()) :: atom()
  def name(server_name) do
    :"FSM.Server.#{server_name}"
  end

  @spec register(Rafty.id(), Rafty.term_index(), Rafty.timestamp()) :: term()
  def register({server_name, node_name}, index, timestamp) do
    GenServer.call({name(server_name), node_name}, {:register, index, timestamp})
  end

  @spec execute(Rafty.id(), Rafty.client_id(), reference(), Rafty.timestamp(), term()) :: term()
  def execute({server_name, node_name}, client_id, ref, timestamp, payload) do
    GenServer.call({name(server_name), node_name}, {:execute, client_id, ref, timestamp, payload})
  end

  @spec query(Rafty.id(), term()) :: term()
  def query({server_name, node_name}, payload) do
    GenServer.call({name(server_name), node_name}, {:query, payload})
  end

  @impl GenServer
  def init(args) do
    {:ok,
     %__MODULE__{
       fsm: args[:fsm],
       fsm_state: args[:fsm].init(),
       ttl: args[:ttl],
       requests: %{}
     }}
  end

  @impl GenServer
  def handle_call({:execute, client_id, ref, timestamp, payload}, _from, state) do
    requests = prune_requests(state.requests, timestamp)

    case Map.get(requests, client_id) do
      nil ->
        {:reply, :non_existent_session, %__MODULE__{state | requests: requests}}

      {last_ref, last_resp, _expiration_timestamp} ->
        if last_ref == ref do
          requests =
            Map.update!(requests, client_id, fn {last_ref, last_resp, _expiration_timestamp} ->
              {last_ref, last_resp, timestamp + state.ttl}
            end)

          {:reply, last_resp, %__MODULE__{state | requests: requests}}
        else
          {resp, fsm_state} = state.fsm.execute(state.fsm_state, payload)

          requests =
            Map.update!(requests, client_id, fn _request_info ->
              {ref, resp, timestamp + state.ttl}
            end)

          {:reply, resp, %__MODULE__{state | requests: requests, fsm_state: fsm_state}}
        end
    end
  end

  @impl GenServer
  def handle_call({:query, payload}, _from, state) do
    resp = state.fsm.query(state.fsm_state, payload)
    {:reply, resp, state}
  end

  @impl GenServer
  def handle_call({:register, index, timestamp}, _from, state) do
    {:reply, {:ok, index},
     %__MODULE__{
       state
       | requests: Map.put(state.requests, index, {nil, nil, timestamp + state.ttl})
     }}
  end

  @spec prune_requests(requests(), Rafty.timestamp()) :: requests()
  defp prune_requests(requests, curr_timestamp),
    # Filtering requests can be optimized using a sorted data structure that supports splitting at a
    # specific key (E.G. treap), but in practice, the number of active clients should be relatively
    # small, so a linear scan should suffice.
    do:
      requests
      |> Enum.filter(fn {_id, {_last_ref, _last_resp, expiration_timestamp}} ->
        curr_timestamp < expiration_timestamp
      end)
      |> Enum.into(%{})
end
