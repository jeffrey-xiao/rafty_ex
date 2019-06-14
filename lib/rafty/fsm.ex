defmodule Rafty.FSM do
  @callback init :: term()
  @callback execute(term(), term()) :: {term(), term()}
  @callback query(term(), term()) :: term()
end
