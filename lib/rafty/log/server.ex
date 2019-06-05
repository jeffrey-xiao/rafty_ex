defmodule Rafty.Log.Server do
  use GenServer

  defstruct [
    :log,
    :log_state
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: name(args[:server_name]))
  end

  def name(server_name) do
    :"LogServer_#{server_name}"
  end

  def get_term_index({server_name, node_name}) do
    GenServer.call(name(server_name), :get_metadata)[:term_index]
  end

  def increment_term_index({server_name, node_name}) do
    metadata = GenServer.call(name(server_name), :get_metadata)

    GenServer.cast(
      name(server_name),
      {:set_metadata, put_in(metadata[:term_index], metadata[:term_index] + 1)}
    )

    metadata[:term_index] + 1
  end

  def set_term_index({server_name, node_name}, term_index) do
    metadata = GenServer.call(name(server_name), :get_metadata)
    GenServer.cast(name(server_name), {:set_metadata, put_in(metadata[:term_index], term_index)})
  end

  def get_voted_for({server_name, node_name}) do
    GenServer.call(name(server_name), :get_metadata)[:voted_for]
  end

  def set_voted_for({server_name, node_name}, voted_for) do
    metadata = GenServer.call(name(server_name), :get_metadata)
    GenServer.cast(name(server_name), {:set_metadata, put_in(metadata[:voted_for], voted_for)})
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
