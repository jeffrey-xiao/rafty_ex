defmodule Rafty.Log.InMemoryStore do
  alias Rafty.Log
  alias Rafty.Log.Metadata

  @behaviour Log

  @type t :: %__MODULE__{
          metadata: Metadata.t(),
          entries: [Rafty.Log.Entry.t()]
        }
  @enforce_keys [:metadata, :entries]
  defstruct [
    :metadata,
    :entries
  ]

  @impl Log
  def init(_server_name) do
    %__MODULE__{
      metadata: %Metadata{},
      entries: []
    }
  end

  @impl Log
  def close(_state), do: :ok

  @impl Log
  def get_metadata(state) do
    state.metadata
  end

  @impl Log
  def set_metadata(state, metadata) do
    %__MODULE__{state | metadata: metadata}
  end

  @impl Log
  def get_entry(state, index) do
    if index == 0, do: nil, else: Enum.at(state.entries, index - 1)
  end

  @impl Log
  def get_entries(state, index) do
    {_head, tail} = Enum.split(state.entries, index - 1)
    tail
  end

  @impl Log
  def append_entries(state, entries, index) do
    {head, tail} = Enum.split(state.entries, index)
    %__MODULE__{state | entries: head ++ Rafty.Log.merge_logs(tail, entries)}
  end

  @impl Log
  def length(state) do
    Kernel.length(state.entries)
  end
end
