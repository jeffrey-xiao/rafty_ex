defmodule RaftyTest do
  use ExUnit.Case
  doctest Rafty

  setup do
    Application.stop(:rafty)
    :ok = Application.start(:rafty)
  end

  test "sample" do
    Rafty.ServersSupervisor.start_server(:a)
    Rafty.ServersSupervisor.start_server(:b)
    Rafty.ServersSupervisor.start_server(:c)
    Process.sleep(5000)
  end
end
