defmodule Rafty.Log.Metadata do
  @type t :: %__MODULE__{term_index: non_neg_integer(), voted_for: Rafty.opt_id()}
  defstruct term_index: 0,
            voted_for: nil
end
