defmodule Rafty.Timer do
  @moduledoc """
  A general-purpose timer that will send a message to `self()` after a specified duration has
  elapsed.
  """

  @enforce_keys [:command]
  defstruct [
    :command,
    :timer_ref,
    :ref
  ]

  @type t :: %__MODULE__{command: atom(), timer_ref: reference() | nil, ref: reference() | nil}

  @doc """
  Creates a new, unset timer that sends `command` to `self()` after a specified duration has
  elapsed.
  """
  @spec new(atom()) :: t()
  def new(command) do
    %__MODULE__{
      command: command,
      timer_ref: nil,
      ref: nil
    }
  end

  @doc """
  Resets the timer with a new timeout. The old timeout may still trigger a message, so you must
  check that the reference sent in the message is `ref` stored in the timer. If the references don't
  match, then the message must be ignored.
  """
  @spec reset(t(), timeout()) :: t()
  def reset(timer, timeout) do
    timer = stop(timer)
    ref = make_ref()
    timer_ref = Process.send_after(self(), {timer.command, ref}, timeout)
    %__MODULE__{timer | timer_ref: timer_ref, ref: ref}
  end

  @doc """
  Stops the timer. The old timeout may still trigger a message, so you must check that the reference
  sent in the message is `ref` stored in the timer. If the references don't match, then the message
  must be ignored.
  """
  @spec stop(t()) :: t()
  def stop(timer) do
    if timer.timer_ref != nil do
      Process.cancel_timer(timer.timer_ref)
    end

    %__MODULE__{timer | timer_ref: nil, ref: nil}
  end
end
