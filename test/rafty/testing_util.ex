defmodule Rafty.TestingUtil do
  @moduledoc false

  def clean_db(server_name), do: File.rm_rf!(Path.join("db", Atom.to_string(server_name)))

  def new_entry(term_index, command, payload) do
    %Rafty.Log.Entry{
      term_index: term_index,
      command: command,
      payload: payload
    }
  end

  def succeed_soon(test_fn, timeout \\ 500, retries \\ 3, backoff_ratio \\ 1) do
    if retries == 0 do
      :timeout
    else
      case test_fn.() do
        {:ok, res} ->
          res

        :retry ->
          Process.sleep(timeout)
          succeed_soon(test_fn, timeout * backoff_ratio, retries - 1, backoff_ratio)
      end
    end
  end
end
