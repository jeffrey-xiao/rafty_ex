defmodule Rafty.TimerTest do
  use ExUnit.Case, async: true

  alias Rafty.Timer

  doctest Rafty.Timer

  test "reset" do
    timer = :test |> Timer.new() |> Timer.reset(10)
    ref = timer.ref
    assert_receive {:test, ^ref}
  end

  test "stop" do
    timer = :test |> Timer.new() |> Timer.reset(10) |> Timer.stop()
    ref = timer.ref
    refute_receive {:test, ^ref}
  end
end
