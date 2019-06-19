defmodule Rafty.Server.ClientRequest do
  @moduledoc """
  `Rafty.Server.ClientRequest` is a request from a client to a Raft group.
  """

  @enforce_keys [:from, :log_index, :type]
  defstruct [
    :from,
    :log_index,
    :type,
    :payload
  ]

  @type t :: %__MODULE__{
          from: GenServer.from(),
          log_index: Rafty.log_index(),
          type: :register | :execute | :query,
          payload: term()
        }
end
