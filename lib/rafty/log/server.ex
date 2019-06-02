defmodule Rafty.Log.Server do
  use GenServer

  def start_link(server_name) do
    GenServer.start_link(__MODULE__, server_name, nam: server_name)
  end

  def name(server_name) do
    :"LogServer_#{server_name}"
  end

  def init(server_name) do
    {:ok, nil}
  end
end
