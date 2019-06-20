defmodule RaftyTest.Util do
  @moduledoc false

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
