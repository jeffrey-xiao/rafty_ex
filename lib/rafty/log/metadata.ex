defmodule Rafty.Log.Metadata do
  @moduledoc """
  Persisted metadata of a Raft log.
  """

  defstruct [
    :voted_for,
    term_index: 0
  ]

  @type t :: %__MODULE__{term_index: Rafty.term_index(), voted_for: Rafty.opt_id()}
end
