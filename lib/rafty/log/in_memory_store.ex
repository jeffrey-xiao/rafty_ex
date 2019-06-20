defmodule Rafty.Log.InMemoryStore do
  @moduledoc """
  Implementation of `Rafty.Log` that stores the entries and metadata in-memory. This store should
  only be used for testing and might yield incorrect results if servers crash and lose data that
  must be persisted for correctness.
  """

  @behaviour Rafty.Log

  alias Rafty.Log
  alias Rafty.Log.Metadata

  @enforce_keys [:metadata, :entries]
  defstruct [
    :metadata,
    :entries
  ]

  @type t :: %__MODULE__{
          metadata: Metadata.t(),
          entries: [Rafty.Log.Entry.t()]
        }

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
  def get_metadata(state), do: state.metadata

  @impl Log
  def set_metadata(state, metadata),
    do: %__MODULE__{state | metadata: metadata}

  @impl Log
  def get_entry(state, index),
    do: if(index == 0, do: nil, else: Enum.at(state.entries, index - 1))

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
  def length(state), do: Kernel.length(state.entries)
end
