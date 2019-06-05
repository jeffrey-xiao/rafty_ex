defmodule Rafty.Log.Entry do
  @type t :: %__MODULE__{term_index: non_neg_integer(), command: term()}
  defstruct term_index: 0,
            command: nil
end
