defmodule Rafty.Log do
  @type state :: any()
  @callback init(Rafty.server_name()) :: state()
  @callback close(state()) :: :ok
  @callback get_metadata(state()) :: Rafty.Log.Metadata.t()
  @callback set_metadata(state(), Rafty.Log.Metadata.t()) :: state()
  @callback get_entry(state(), Rafty.log_index()) :: any()
  @callback get_entries(state(), Rafty.log_index()) :: [Rafty.Log.Entry.t()]
  @callback append_entries(state(), [Rafty.Log.Entry.t()], Rafty.log_index()) :: state()
  @callback length(state()) :: non_neg_integer()

  @spec merge_logs([Rafty.Log.Entry.t()], [Rafty.Log.Entry.t()]) :: [Rafty.Log.Entry.t()]
  def merge_logs([], new), do: new
  def merge_logs(old, []), do: old

  def merge_logs([old_head | old_tail], [new_head | new_tail] = new) do
    if old_head.term_index != new_head.term_index,
      do: new,
      else: merge_logs(old_tail, new_tail)
  end
end
