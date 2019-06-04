defmodule Rafty.Log.InMemoryStore do
  alias Rafty.Log.Store

  @behaviour Store

  @enforce_keys [:current_term_index, :voted_for, :entries]
  defstruct [
    :current_term_index,
    :voted_for,
    :entries
  ]

  @impl Store
  def init(_server_name) do
    %__MODULE__{
      current_term_index: 0,
      voted_for: nil,
      entries: []
    }
  end

  @impl Store
  def get_metadata(state) do
    %{
      current_term_index: state.current_term_index,
      voted_for: state.voted_for
    }
  end

  @impl Store
  def set_metadata(state, metadata) do
    struct(state, metadata)
  end

  @impl Store
  def get_entry(state, index) do
    Enum.at(state.entries, index - 1)
  end

  @impl Store
  def get_tail(state, index) do
    {_head, tail} = Enum.split(state.entries, index)
    tail
  end

  @impl Store
  def append_entries(state, entries, index) do
    {head, _tail} = Enum.split(state.entries, index)
    %{state | entries: head ++ entries}
  end

  @impl Store
  def length(state) do
    Kernel.length(state.entries)
  end
end
