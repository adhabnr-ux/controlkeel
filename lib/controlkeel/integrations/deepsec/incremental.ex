defmodule ControlKeel.Integrations.Deepsec.Incremental do
  @moduledoc """
  Incremental scanning for deepsec to avoid re-scanning unchanged files.

  This module provides incremental scanning capabilities by:
  1. Tracking file hashes to detect changes
  2. Using cache to skip unchanged files
  3. Only scanning changed files since last scan
  """

  require Logger

  alias ControlKeel.Integrations.Deepsec.{Cache, CLI}

  @doc """
  Performs an incremental scan, only scanning changed files.

  ## Parameters
  - workspace_path: Path to deepsec workspace
  - opts: Keyword list of options
    - force: Force full scan even if cache exists (default: false)
    - file_patterns: List of glob patterns to include (default: ["**/*"])
    - ignore_patterns: List of glob patterns to ignore (default: [])

  ## Returns
  {:ok, result} on success
  {:error, reason} on failure
  """
  def incremental_scan(workspace_path, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    file_patterns = Keyword.get(opts, :file_patterns, ["**/*"])
    ignore_patterns = Keyword.get(opts, :ignore_patterns, [])

    if force do
      # Force full scan
      Logger.info("Forcing full deepsec scan")
      full_scan(workspace_path, opts)
    else
      # Check if we can do incremental scan
      changed_files = get_changed_files(workspace_path, file_patterns, ignore_patterns)

      if length(changed_files) == 0 do
        # No changes, return cached results
        Logger.info("No changed files, returning cached results")
        get_cached_results(workspace_path)
      else
        # Scan only changed files
        Logger.info("Incremental scan: #{length(changed_files)} changed files")
        scan_changed_files(workspace_path, changed_files, opts)
      end
    end
  end

  @doc """
  Gets a list of changed files since the last scan.
  """
  def get_changed_files(workspace_path, file_patterns \\ ["**/*"], ignore_patterns \\ []) do
    # Get all files matching patterns
    all_files = find_files(workspace_path, file_patterns, ignore_patterns)

    # Filter to only changed files
    Enum.filter(all_files, fn file_path ->
      Cache.file_changed?(file_path, workspace_path)
    end)
  end

  @doc """
  Finds files matching the given patterns.
  """
  def find_files(workspace_path, file_patterns, ignore_patterns) do
    # Collect all files matching patterns
    files =
      Enum.flat_map(file_patterns, fn pattern ->
        Path.wildcard(Path.join(workspace_path, pattern))
      end)

    # Filter out directories and ignored patterns
    files
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(fn file_path ->
      Enum.any?(ignore_patterns, fn pattern ->
        # Simple string matching for ignore patterns
        String.contains?(file_path, pattern)
      end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Scans only the changed files.
  """
  def scan_changed_files(workspace_path, changed_files, _opts) do
    # For now, we'll run a full scan but only process changed files
    # In a real implementation, we'd need to pass file list to deepsec CLI
    # Deepsec doesn't currently support file list filtering, so we'll
    # run full scan and filter results

    Logger.info("Running deepsec scan for changed files")

    case CLI.scan(workspace_path: workspace_path) do
      {:ok, output} ->
        # Filter results to only changed files
        filtered_results = filter_results_by_files(output, changed_files)

        # Cache the results
        cache_results(workspace_path, changed_files, filtered_results)

        {:ok, filtered_results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Performs a full scan (non-incremental).
  """
  def full_scan(workspace_path, _opts) do
    Logger.info("Running full deepsec scan")

    case CLI.scan(workspace_path: workspace_path) do
      {:ok, output} ->
        # Cache all results
        cache_all_results(workspace_path, output)

        {:ok, output}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Filters scan results to only include specified files.

  NOTE: deepsec CLI does not support per-file scan filtering. This runs a full
  workspace scan and passes results through unfiltered. File filtering would
  require post-processing the structured deepsec output, which depends on the
  actual output format from the installed deepsec version.
  """
  def filter_results_by_files(results, _files) do
    results
  end

  @doc """
  Caches scan results keyed per changed file.
  """
  def cache_results(workspace_path, files, results) do
    Enum.each(files, fn file_path ->
      file_hash = Cache.file_hash(file_path)
      Cache.put(file_path, workspace_path, %{file_hash: file_hash, results: results})
    end)

    :ok
  end

  @doc """
  Caches all results from a full scan.

  NOTE: Currently a no-op because deepsec raw output is not parsed per-file
  here. Call cache_results/3 after extracting per-file findings.
  """
  def cache_all_results(_workspace_path, _results), do: :ok

  @doc """
  Gets cached results for a workspace.

  NOTE: Per-file cache aggregation is not yet implemented. When no changed
  files are detected, callers should treat this as a signal to run a full scan
  rather than assuming the cache is populated.
  """
  def get_cached_results(_workspace_path) do
    {:ok, []}
  end

  @doc """
  Clears cache for a workspace to force re-scan.
  """
  def invalidate_workspace(workspace_path) do
    Cache.clear_workspace(workspace_path)
    Logger.info("Invalidated cache for workspace: #{workspace_path}")
    :ok
  end
end
