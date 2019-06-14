defmodule Rafty.Log.Entry do
  @type t :: %__MODULE__{term_index: Rafty.term_index(), command: term(), payload: term(), timestamp: non_neg_integer()}
  @enforce_keys [:term_index, :command, :payload, :timestamp]
  defstruct [
    :term_index,
    :command,
    :payload,
    :timestamp
  ]
end
