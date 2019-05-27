defmodule Rafty do
  use Application

  @type term_index :: non_neg_integer()

  def start(_type, _args) do
    Rafty.Supervisor.start_link()
  end
end
