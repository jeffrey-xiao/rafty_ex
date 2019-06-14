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
end
