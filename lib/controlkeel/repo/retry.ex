defmodule ControlKeel.Repo.Retry do
  @moduledoc """
  Shared SQLite "database busy" retry helpers.

  SQLite returns a "Database busy" error under concurrent writes. These helpers
  wrap `Repo.transaction`, `Repo.insert`, and `Repo.update` with exponential
  backoff so callers don't have to duplicate the rescue-and-retry pattern.
  """

  alias ControlKeel.Repo

  @default_backoff_ms [0, 250, 750, 1_500, 3_000, 5_000]

  def busy_error?(error) do
    error
    |> Exception.message()
    |> String.contains?("Database busy")
  end

  def transaction_with_busy_retry(operation, backoff_ms \\ @default_backoff_ms, attempt \\ 0) do
    Repo.transaction(operation)
  rescue
    error ->
      if busy_error?(error) and attempt < length(backoff_ms) - 1 do
        Process.sleep(Enum.at(backoff_ms, attempt + 1))
        transaction_with_busy_retry(operation, backoff_ms, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  def insert_with_busy_retry(changeset, backoff_ms \\ @default_backoff_ms, attempt \\ 0) do
    Repo.insert(changeset)
  rescue
    error ->
      if busy_error?(error) and attempt < length(backoff_ms) - 1 do
        Process.sleep(Enum.at(backoff_ms, attempt + 1))
        insert_with_busy_retry(changeset, backoff_ms, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  def update_with_busy_retry(changeset, backoff_ms \\ @default_backoff_ms, attempt \\ 0) do
    Repo.update(changeset)
  rescue
    error ->
      if busy_error?(error) and attempt < length(backoff_ms) - 1 do
        Process.sleep(Enum.at(backoff_ms, attempt + 1))
        update_with_busy_retry(changeset, backoff_ms, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end

  def update_with_busy_retry!(changeset, backoff_ms \\ @default_backoff_ms, attempt \\ 0) do
    Repo.update!(changeset)
  rescue
    error ->
      if busy_error?(error) and attempt < length(backoff_ms) - 1 do
        Process.sleep(Enum.at(backoff_ms, attempt + 1))
        update_with_busy_retry!(changeset, backoff_ms, attempt + 1)
      else
        reraise error, __STACKTRACE__
      end
  end
end
