defmodule Rafty.Log.Metadata do
  @moduledoc """
  Persisted metadata of a Raft log.
  """

  defstruct term_index: 0,
            voted_for: nil

  @type t :: %__MODULE__{term_index: Rafty.term_index(), voted_for: Rafty.opt_id()}
end
