defmodule Rafty.Server.State do
  defstruct current_term_index: 0,
            voted_for: nil,
            log: [],
            commit_index: 0,
            last_applied: 0,
            next_index: %{},
            match_index: %{}
end
