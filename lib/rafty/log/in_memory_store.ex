defmodule Rafty.Log.InMemoryStore do
  alias Rafty.Log.Store

  @behaviour Store

  @type t :: %__MODULE__{
          term_index: non_neg_integer(),
          voted_for: Rafty.id() | nil,
          entries: [Rafty.Log.Entry.t()]
        }
  @enforce_keys [:term_index, :voted_for, :entries]
  defstruct [
    :term_index,
    :voted_for,
    :entries
  ]

  @impl Store
  def init(_server_name) do
    %__MODULE__{
      term_index: 0,
      voted_for: nil,
      entries: []
    }
  end

  @impl Store
  def get_metadata(state) do
    %{
      term_index: state.term_index,
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
    {_head, tail} = Enum.split(state.entries, index - 1)
    tail
  end

  @impl Store
  def append_entries(state, entries, index) do
    {head, _tail} = Enum.split(state.entries, index)
    %__MODULE__{state | entries: head ++ entries}
  end

  @impl Store
  def length(state) do
    Kernel.length(state.entries)
  end
end
