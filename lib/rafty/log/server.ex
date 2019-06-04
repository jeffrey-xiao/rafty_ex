defmodule Rafty.Log.Server do
  use GenServer

  defstruct [
    :log,
    :log_state
  ]

  def start_link({server_name, _log} = args) do
    GenServer.start_link(__MODULE__, args, name: name(server_name))
  end

  def name(server_name) do
    :"LogServer_#{server_name}"
  end

  def get_metadata({server_name, node_name}) do
    GenServer.call(name(server_name), :get_metadata)
  end

  def set_metadata({server_name, node_name}, metadata) do
    GenServer.cast(name(server_name), {:set_metadata, metadata})
  end

  def get_entry({server_name, node_name}, index) do
    GenServer.call(name(server_name), {:get_entry, index})
  end

  def get_tail({server_name, node_name}, index) do
    GenServer.call(name(server_name), {:get_tail, index})
  end

  def append_entries({server_name, node_name}, entries, index) do
    GenServer.cast(name(server_name), {:append_entries, entries, index})
  end

  def length({server_name, node_name}) do
    GenServer.call(name(server_name), :length)
  end

  @impl GenServer
  def init({server_name, log}) do
    {:ok, %__MODULE__{log: log, log_state: log.init(server_name)}}
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
  def handle_call({:get_tail, index}, _from, state) do
    {:reply, state.log.get_tail(state.log_state, index), state}
  end

  @impl GenServer
  def handle_call(:length, _from, state) do
    {:reply, state.log.length(state.log_state), state}
  end

  @impl GenServer
  def handle_cast({:set_metadata, metadata}, state) do
    {:noreply, state.log_state |> put_in(state.log.set_metadata(state.log_state, metadata))}
  end

  @impl GenServer
  def handle_cast({:append_entries, entries, index}, state) do
    {:noreply,
     state.log_state |> put_in(state.log.append_entries(state.log_state, entries, index))}
  end
end
