defmodule Rafty.Log do
  @moduledoc """
  A behavior that defines the log interface that the Raft protocol uses to persist data.
  """

  @typedoc """
  The state of the log.
  """
  @type state :: term()

  @doc """
  Initializes the log of the specified server.
  """
  @callback init(Rafty.server_name()) :: state()

  @doc """
  Closes the log with the specified state.
  """
  @callback close(state()) :: :ok

  @doc """
  Returns the metadata recorded in the log with the specified state.
  """
  @callback get_metadata(state()) :: Rafty.Log.Metadata.t()

  @doc """
  Sets of the metadata in the log with the specified state.
  """
  @callback set_metadata(state(), Rafty.Log.Metadata.t()) :: state()

  @doc """
  Returns an entry in the log with the specified state.
  """
  @callback get_entry(state(), Rafty.log_index()) :: Rafty.Log.Entry.t()

  @doc """
  Returns a list of entries in the log with the specified state.
  """
  @callback get_entries(state(), Rafty.log_index()) :: [Rafty.Log.Entry.t()]

  @doc """
  Appends a list of entries in the log with the specified state.
  """
  @callback append_entries(state(), [Rafty.Log.Entry.t()], Rafty.log_index()) :: state()

  @doc """
  Returns the length of the log with the specified state.
  """
  @callback length(state()) :: non_neg_integer()

  @doc """
  Merges two lists of logs together. All entries after the first conflict are removed from `old` and
  replaced with the entries from `new`. If there are no conflicts, and `new` is missing entries,
  then this function is a no-op.
  """
  @spec merge_logs([Rafty.Log.Entry.t()], [Rafty.Log.Entry.t()]) :: [Rafty.Log.Entry.t()]
  def merge_logs([], new), do: new
  def merge_logs(old, []), do: old

  def merge_logs([old_head | old_tail], [new_head | new_tail] = new) do
    if old_head.term_index != new_head.term_index,
      do: new,
      else: [old_head | merge_logs(old_tail, new_tail)]
  end
end
