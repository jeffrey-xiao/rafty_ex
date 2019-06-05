defmodule RaftyTest.Util do
  def succeed_soon(test_fn, timeout \\ 500, retries \\ 3, backoff_ratio \\ 1) do
    if retries == 0 do
      :timeout
    else
      test_fn.()
      |> case do
        {res, true} ->
          res

        {_, false} ->
          Process.sleep(timeout)
          succeed_soon(test_fn, timeout * backoff_ratio, retries - 1, backoff_ratio)
      end
    end
  end
end
