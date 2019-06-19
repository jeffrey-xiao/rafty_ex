defmodule Rafty.FSM do
  @moduledoc """
  A behavior that defines the finite state machine interface that the Raft protocol modifies and
  reads from.
  """

  @typedoc """
  The state of the finite state machine.
  """
  @type state :: term()

  @doc """
  Initializes a finite state machine.
  """
  @callback init :: state()

  @doc """
  Executes a command that may modify the finite state machine with the specified state.
  """
  @callback execute(state(), term()) :: {state(), term()}

  @doc """
  Executes a read-only query of the finite state machine with the specified state.
  """
  @callback query(state(), term()) :: term()
end
