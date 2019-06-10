defmodule Rafty.Log.Entry do
  @type t :: %__MODULE__{term_index: non_neg_integer(), command: term(), payload: term()}
  @enforce_keys [:term_index, :command, :payload]
  defstruct [
    :term_index,
    :command,
    :payload
  ]
end
