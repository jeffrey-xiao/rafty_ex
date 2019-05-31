defmodule Rafty.FSM do
  @callback init() :: any()
  @callback execute(any(), any()) :: {any(), any()}
  @callback query(any(), any()) :: any()
end
