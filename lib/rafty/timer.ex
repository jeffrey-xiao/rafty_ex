defmodule Rafty.Timer do
  @type t :: %__MODULE__{command: atom(), timer_ref: reference() | nil, ref: reference() | nil}

  @enforce_keys [:command]
  defstruct [
    :command,
    :timer_ref,
    :ref
  ]

  @spec new(atom) :: t()
  def new(command) do
    %__MODULE__{
      command: command,
      timer_ref: nil,
      ref: nil
    }
  end

  @spec reset(t(), non_neg_integer()) :: t()
  def reset(timer, timeout) do
    timer = stop(timer)
    ref = make_ref()
    timer_ref = Process.send_after(self(), {timer.command, ref}, timeout)
    %{timer | timer_ref: timer_ref, ref: ref}
  end

  @spec stop(t()) :: t()
  def stop(timer) do
    if timer.timer_ref != nil do
      Process.cancel_timer(timer.timer_ref)
    end

    %{timer | timer_ref: nil, ref: nil}
  end
end
