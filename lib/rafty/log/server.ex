defmodule Rafty.Log.Server do
  use GenServer

  @type t :: %__MODULE__{log: module(), log_state: term()}
  defstruct [
    :log,
    :log_state
  ]

  @spec start_link(Rafty.args()) :: {:ok, term()} | {:error, term()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: name(args[:server_name]))
  end

  @spec name(Rafty.server_name()) :: atom()
  def name(server_name) do
    :"LogServer_#{server_name}"
  end

  @spec get_term_index(Rafty.id()) :: non_neg_integer()
  def get_term_index({server_name, node_name}) do
    GenServer.call({name(server_name), node_name}, :get_metadata)[:term_index]
  end

  @spec increment_term_index(Rafty.id()) :: non_neg_integer()
  def increment_term_index({server_name, node_name}) do
    metadata = GenServer.call({name(server_name), node_name}, :get_metadata)

    GenServer.call(
      name(server_name),
      {:set_metadata, put_in(metadata[:term_index], metadata[:term_index] + 1)}
    )

    metadata[:term_index] + 1
  end

  @spec set_term_index(Rafty.id(), non_neg_integer()) :: :ok
  def set_term_index({server_name, node_name}, term_index) do
    metadata = GenServer.call({name(server_name), node_name}, :get_metadata)

    GenServer.call(
      {name(server_name), node_name},
      {:set_metadata, put_in(metadata[:term_index], term_index)}
    )
  end

  @spec get_voted_for(Rafty.id()) :: Rafty.id()
  def get_voted_for({server_name, node_name}) do
    GenServer.call({name(server_name), node_name}, :get_metadata)[:voted_for]
  end

  @spec set_voted_for(Rafty.id(), Rafty.id() | nil) :: :ok
  def set_voted_for({server_name, node_name}, voted_for) do
    metadata = GenServer.call({name(server_name), node_name}, :get_metadata)
    GenServer.call(name(server_name), {:set_metadata, put_in(metadata[:voted_for], voted_for)})
  end

  @spec get_entry(Rafty.id(), non_neg_integer()) :: Rafty.Log.Entry.t() | nil
  def get_entry({server_name, node_name}, index) do
    GenServer.call({name(server_name), node_name}, {:get_entry, index})
  end

  @spec get_entries(Rafty.id(), non_neg_integer()) :: [Rafty.Log.Entry.t()]
  def get_entries({server_name, node_name}, index) do
    GenServer.call({name(server_name), node_name}, {:get_entries, index})
  end

  @spec append_entries(Rafty.id(), [Rafty.Log.Entry.t()], non_neg_integer()) :: :ok
  def append_entries({server_name, node_name}, entries, index) do
    GenServer.call({name(server_name), node_name}, {:append_entries, entries, index})
  end

  @spec length(Rafty.id()) :: non_neg_integer()
  def length({server_name, node_name}) do
    GenServer.call({name(server_name), node_name}, :length)
  end

  @impl GenServer
  def init(args) do
    {:ok, %__MODULE__{log: args[:log], log_state: args[:log].init(args[:server_name])}}
  end

  @impl GenServer
  def handle_call(:get_metadata, _from, state) do
    {:reply, state.log.get_metadata(state.log_state), state}
  end

  @impl GenServer
  def handle_call({:get_entry, index}, _from, state) do
    {:reply, state.log.get_entry(state.log_state, index), state}
  end

  @impl GenServer
  def handle_call({:get_entries, index}, _from, state) do
    {:reply, state.log.get_entries(state.log_state, index), state}
  end

  @impl GenServer
  def handle_call(:length, _from, state) do
    {:reply, state.log.length(state.log_state), state}
  end

  @impl GenServer
  def handle_call({:set_metadata, metadata}, _from, state) do
    {:reply, :ok, state.log_state |> put_in(state.log.set_metadata(state.log_state, metadata))}
  end

  @impl GenServer
  def handle_call({:append_entries, entries, index}, _from, state) do
    {:reply, :ok,
     state.log_state |> put_in(state.log.append_entries(state.log_state, entries, index))}
  end
end
