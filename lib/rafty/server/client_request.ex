defmodule Rafty.Server.ClientRequest do
  @type t :: %__MODULE__{
          from: GenServer.from(),
          log_index: Rafty.log_index(),
          type: :register | :execute | :query,
          payload: term()
        }
  @enforce_keys [:from, :log_index, :type]
  defstruct [
    :from,
    :log_index,
    :type,
    :payload
  ]
end
