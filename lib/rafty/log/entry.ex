defmodule Rafty.Log.Entry do
  @moduledoc """
  An entry of a Raft log.
  """

  @enforce_keys [:term_index, :command, :payload]
  defstruct [
    :client_id,
    :ref,
    :timestamp,
    :term_index,
    :command,
    :payload
  ]

  @type t :: %__MODULE__{
          client_id: Rafty.client_id() | nil,
          timestamp: Rafty.timestamp() | nil,
          ref: reference() | nil,
          term_index: Rafty.term_index(),
          command: term(),
          payload: term()
        }
end
