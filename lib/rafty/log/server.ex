defmodule Rafty.Log.Server do
  @moduledoc """
  A server that is the interface to the underlying Raft log.
  """

  use GenServer

  @enforce_keys [:log, :log_state]
  defstruct [
    :log,
    :log_state
  ]

  @type t :: %__MODULE__{log: module(), log_state: term()}

  @doc """
  Returns the name of the server.
  """
  @spec name(Rafty.server_name()) :: atom()
  def name(server_name) do
    :"Log.Server.#{server_name}"
  end

  @doc """
  Starts a `Rafty.Log.Server` process linked to the current process.
  """
  @spec start_link(Rafty.args()) :: {:ok, term()} | {:error, term()}
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: name(args[:server_name]))
  end

  @doc """
  Stops a `Rafty.Log.Server` process.
  """
  @spec stop(Rafty.id()) :: :ok
  def stop({server_name, node_name}) do
    :ok = GenServer.call({name(server_name), node_name}, :close)
    GenServer.stop({name(server_name), node_name})
  end

  @doc """
  Returns the term of the specified server.
  """
  @spec get_term_index(Rafty.id()) :: Rafty.term_index()
  def get_term_index({server_name, node_name}) do
    GenServer.call({name(server_name), node_name}, :get_metadata).term_index
  end

  @doc """
  Increments the term of the specified server.
  """
  @spec increment_term_index(Rafty.id()) :: Rafty.term_index()
  def increment_term_index({server_name, node_name}) do
    metadata = GenServer.call({name(server_name), node_name}, :get_metadata)

    GenServer.call(
      name(server_name),
      {:set_metadata, put_in(metadata.term_index, metadata.term_index + 1)}
    )

    metadata.term_index + 1
  end

  @doc """
  Sets the term of the specified server to `term_index`.
  """
  @spec set_term_index(Rafty.id(), Rafty.term_index()) :: :ok
  def set_term_index({server_name, node_name}, term_index) do
    metadata = GenServer.call({name(server_name), node_name}, :get_metadata)

    GenServer.call(
      {name(server_name), node_name},
      {:set_metadata, put_in(metadata.term_index, term_index)}
    )
  end

  @doc """
  Returns the server that the specified server voted for, if any.
  """
  @spec get_voted_for(Rafty.id()) :: Rafty.id() | nil
  def get_voted_for({server_name, node_name}) do
    GenServer.call({name(server_name), node_name}, :get_metadata).voted_for
  end

  @doc """
  Sets the server that the specified serverd voted for, if any.
  """
  @spec set_voted_for(Rafty.id(), Rafty.id() | nil) :: :ok
  def set_voted_for({server_name, node_name}, voted_for) do
    metadata = GenServer.call({name(server_name), node_name}, :get_metadata)
    GenServer.call(name(server_name), {:set_metadata, put_in(metadata.voted_for, voted_for)})
  end

  @doc """
  Returns the entry at `index` of the specified server's Raft log.
  """
  @spec get_entry(Rafty.id(), Rafty.log_index()) :: Rafty.Log.Entry.t() | nil
  def get_entry({server_name, node_name}, index) do
    GenServer.call({name(server_name), node_name}, {:get_entry, index})
  end

  @doc """
  Returns a list of entries from `index` to the end of the specified server's Raft log.
  """
  @spec get_entries(Rafty.id(), Rafty.log_index()) :: [Rafty.Log.Entry.t()]
  def get_entries({server_name, node_name}, index) do
    GenServer.call({name(server_name), node_name}, {:get_entries, index})
  end

  @doc """
  Appends a list of entries to `index` of the specified server's Raft log.
  """
  @spec append_entries(Rafty.id(), [Rafty.Log.Entry.t()], Rafty.log_index()) :: :ok
  def append_entries({server_name, node_name}, entries, index) do
    GenServer.call({name(server_name), node_name}, {:append_entries, entries, index})
  end

  @doc """
  Returns the length of the specified server's Raft log.
  """
  @spec length(Rafty.id()) :: non_neg_integer()
  def length({server_name, node_name}) do
    GenServer.call({name(server_name), node_name}, :length)
  end

  @impl GenServer
  def init(args) do
    {:ok, %__MODULE__{log: args[:log], log_state: args[:log].init(args[:server_name])}}
  end

  @impl GenServer
  def handle_call(:close, _from, state) do
    {:reply, state.log.close(state.log_state), state}
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
