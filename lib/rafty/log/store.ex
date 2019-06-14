defmodule Rafty.Log.Store do
  @type state :: any()
  @callback init(Rafty.server_name()) :: state()
  @callback close(state()) :: :ok
  @callback get_metadata(state()) :: Rafty.Log.Metadata.t()
  @callback set_metadata(state(), Rafty.Log.Metadata.t()) :: state()
  @callback get_entry(state(), non_neg_integer()) :: any()
  @callback get_entries(state(), non_neg_integer()) :: [Rafty.Log.Entry.t()]
  @callback append_entries(state(), [Rafty.Log.Entry.t()], non_neg_integer()) :: state()
  @callback length(state()) :: non_neg_integer()
end
