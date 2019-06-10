defmodule Rafty.Log.Store do
  @type state :: any()
  @callback init(Rafty.server_name()) :: state()
  @callback get_metadata(state()) :: %{term_index: non_neg_integer(), voted_for: Rafty.id() | nil}
  @callback set_metadata(state(), %{}) :: state()
  @callback get_entry(state(), non_neg_integer()) :: any()
  @callback get_entries(state(), non_neg_integer()) :: [Rafty.Log.Entry.t()]
  @callback append_entries(state(), [Rafty.Log.Entry.t()], non_neg_integer()) :: state()
  @callback length(state()) :: non_neg_integer()
end
