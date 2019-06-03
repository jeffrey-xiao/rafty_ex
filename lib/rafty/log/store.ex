defmodule Rafty.Log.Store do
  @type state :: any()
  @callback init(atom()) :: state()
  @callback get_metadata(state()) :: any()
  @callback set_metadata(state(), any()) :: state()
  @callback get_entry(state(), pos_integer()) :: any()
  @callback append_entries(state(), pos_integer(), any()) :: state()
end
