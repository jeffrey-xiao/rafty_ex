defmodule Rafty.Timer do
  @enforce_keys [:command]
  defstruct [
    :command,
    :timer_ref,
    :ref
  ]

  def new(command) do
    %__MODULE__{
      command: command,
      timer_ref: nil,
      ref: nil
    }
  end

  def reset(timer, timeout) do
    timer = stop(timer)
    ref = make_ref()
    timer_ref = Process.send_after(self(), {timer.command, ref}, timeout)
    %{timer | timer_ref: timer_ref, ref: ref}
  end

  def stop(timer) do
    if timer.timer_ref != nil do
      Process.cancel_timer(timer.timer_ref)
    end

    %{timer | timer_ref: nil, ref: nil}
  end
end
