defmodule Rafty do
  use Application

  @type term_index :: non_neg_integer()

  @election_time_out 250

  def start(_type, _args) do
    Rafty.Supervisor.start_link()
  end
end
