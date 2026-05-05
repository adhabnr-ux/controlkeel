defmodule ControlKeel.Integrations.Deepsec.Cache do
  @moduledoc """
  Cache for deepsec scan results to avoid re-scanning unchanged files.

  This module provides a simple ETS-based cache that stores scan results
  keyed by file hash and workspace. This enables incremental scanning by
  skipping files that haven't changed since the last scan.
  """

  use GenServer

  require Logger

  @table_name :deepsec_scan_cache
  @ttl_hours 24

  ## Client API

  @doc """
  Starts the cache server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets cached scan results for a file.
  """
  def get(file_path, workspace_path) do
    case :ets.lookup(@table_name, cache_key(file_path, workspace_path)) do
      [{_key, result, timestamp}] ->
        if expired?(timestamp) do
          # Cache entry expired
          :ets.delete(@table_name, cache_key(file_path, workspace_path))
          :miss
        else
          {:hit, result}
        end

      [] ->
        :miss
    end
  end

  @doc """
  Puts scan results in the cache.
  """
  def put(file_path, workspace_path, result) do
    :ets.insert(
      @table_name,
      {cache_key(file_path, workspace_path), result, System.system_time(:second)}
    )

    :ok
  end

  @doc """
  Clears the cache for a specific workspace.
  """
  def clear_workspace(workspace_path) do
    # Get all keys and filter manually
    all_keys = :ets.tab2list(@table_name) |> Enum.map(fn {key, _result, _timestamp} -> key end)

    keys_to_delete =
      Enum.filter(all_keys, fn key ->
        String.starts_with?(key, workspace_path)
      end)

    Enum.each(keys_to_delete, &:ets.delete(@table_name, &1))
    :ok
  end

  @doc """
  Clears the entire cache.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Gets cache statistics.
  """
  def stats do
    size = :ets.info(@table_name, :size)
    memory = :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)

    %{
      size: size,
      memory_bytes: memory,
      memory_mb: memory / (1024 * 1024)
    }
  end

  @doc """
  Computes a cache key for a file.
  """
  def cache_key(file_path, workspace_path) do
    "#{workspace_path}:#{file_path}"
  end

  @doc """
  Computes a hash for a file to detect changes.
  """
  def file_hash(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

      {:error, _} ->
        nil
    end
  end

  @doc """
  Checks if a file has changed since the last scan.
  """
  def file_changed?(file_path, workspace_path, current_hash \\ nil) do
    current_hash = current_hash || file_hash(file_path)

    case get(file_path, workspace_path) do
      {:hit, %{file_hash: cached_hash}} ->
        current_hash != cached_hash

      _ ->
        true
    end
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    Logger.info("Deepsec scan cache started")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:clear_workspace, workspace_path}, state) do
    pattern =
      :ets.fun2ms(fn {key, _result, _timestamp} ->
        if String.starts_with?(key, workspace_path) do
          key
        end
      end)

    keys = :ets.select(@table_name, pattern)
    Enum.each(keys, &:ets.delete(@table_name, &1))
    {:noreply, state}
  end

  ## Private Functions

  defp expired?(timestamp) do
    now = System.system_time(:second)
    ttl_seconds = @ttl_hours * 3600
    now - timestamp > ttl_seconds
  end
end
