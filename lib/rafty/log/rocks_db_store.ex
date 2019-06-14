defmodule Rafty.Log.RocksDBStore do
  alias Rafty.Log.{Entry, Metadata, Store}

  @metadata_key <<"metadata">>
  @db_options [create_if_missing: true]

  @behaviour Store

  @type t :: %__MODULE__{
          db: :rocksdb.db_handle(),
          path: charlist(),
          metadata: Metadata.t(),
          length: non_neg_integer()
        }
  @enforce_keys [:db, :path, :metadata, :length]
  defstruct [
    :db,
    :path,
    :metadata,
    :length
  ]

  @impl Store
  def init(server_name) do
    path = Path.join("db", Atom.to_string(server_name)) |> to_charlist()
    {:ok, db} = :rocksdb.open(path, @db_options)

    %__MODULE__{
      db: db,
      path: path,
      metadata: %Metadata{},
      length: 0
    }
    |> populate_metadata()
    |> populate_length()
  end

  @impl Store
  def close(state) do
    :rocksdb.close(state.path)
  end

  @impl Store
  def get_metadata(state), do: state.metadata

  @impl Store
  def set_metadata(state, metadata) do
    :ok = :rocksdb.put(state.db, @metadata_key, :erlang.term_to_binary(metadata), [])
    %__MODULE__{state | metadata: metadata}
  end

  @impl Store
  def get_entry(state, index) do
    case :rocksdb.get(state.db, :erlang.term_to_binary(index), []) do
      {:ok, res} -> :erlang.binary_to_term(res)
      :not_found -> nil
      {:error, err} -> raise "rocksdb: #{inspect(err)}"
    end
  end

  @impl Store
  def get_entries(state, index) do
    {:ok, iter} = :rocksdb.iterator(state.db, [])

    case :rocksdb.iterator_move(iter, {:seek, :erlang.term_to_binary(index)}) do
      {:ok, _key, value} ->
        [:erlang.binary_to_term(value)] |> get_entries_impl(iter) |> Enum.reverse()

      {:error, :invalid_iterator} ->
        :rocksdb.iterator_close(iter)
        []
    end
  end

  @spec get_entries_impl([Entry.t()], :rocksdb.itr_handle()) :: [Entry.t()]
  defp get_entries_impl(entries, iter) do
    case :rocksdb.iterator_move(iter, :next) do
      {:ok, _key, value} ->
        get_entries_impl([:erlang.binary_to_term(value) | entries], iter)

      {:error, :invalid_iterator} ->
        :rocksdb.iterator_close(iter)
        entries
    end
  end

  @impl Store
  def append_entries(state, entries, index) do
    length = index + Kernel.length(entries)
    :ok = :rocksdb.delete_range(state.db, :erlang.term_to_binary(index + 1), <<132>>, [])

    entries
    |> Enum.with_index(index + 1)
    |> Enum.each(fn {entry, index} ->
      :ok =
        :rocksdb.put(state.db, :erlang.term_to_binary(index), :erlang.term_to_binary(entry), [])
    end)

    %__MODULE__{state | length: length}
  end

  @impl Store
  def length(state), do: state.length

  @spec populate_metadata(t()) :: t()
  defp populate_metadata(state) do
    case :rocksdb.get(state.db, @metadata_key, []) do
      {:ok, res} ->
        %__MODULE__{state | metadata: :erlang.binary_to_term(res)}

      :not_found ->
        set_metadata(state, state.metadata)

      {:error, err} ->
        raise "rocksdb: #{inspect(err)}"
    end
  end

  @spec populate_length(t()) :: t()
  defp populate_length(state) do
    {:ok, iter} = :rocksdb.iterator(state.db, [])

    length =
      case :rocksdb.iterator_move(iter, {:seek, :erlang.term_to_binary(1)}) do
        {:ok, _key, _value} ->
          populate_length_impl(1, iter)

        {:error, :invalid_iterator} ->
          :rocksdb.iterator_close(iter)
          0
      end

    %__MODULE__{state | length: length}
  end

  @spec populate_length_impl(non_neg_integer(), :rocksdb.itr_handle()) :: non_neg_integer()
  defp populate_length_impl(length, iter) do
    case :rocksdb.iterator_move(iter, :next) do
      {:ok, _key, _value} ->
        populate_length_impl(length + 1, iter)

      {:error, :invalid_iterator} ->
        :rocksdb.iterator_close(iter)
        length
    end
  end
end
