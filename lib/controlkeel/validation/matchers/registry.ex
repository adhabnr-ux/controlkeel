defmodule ControlKeel.Validation.Matchers.Registry do
  @moduledoc """
  Registry for managing validation matchers.

  This module provides a centralized registry for matchers,
  supporting built-in security matchers and custom user-defined matchers.
  """

  use Agent

  alias ControlKeel.Validation.Matchers.Matcher

  @doc """
  Starts the matcher registry.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Checks if a matcher with the given slug is registered.
  """
  def has_key?(slug) do
    Agent.get(__MODULE__, fn state ->
      Map.has_key?(state, slug)
    end)
  end

  @doc """
  Registers a matcher in the registry.

  ## Parameters
  - matcher: A Matcher struct

  ## Returns
  :ok or raises if slug is already registered
  """
  def register(%Matcher{} = matcher) do
    if has_key?(matcher.slug) do
      raise "Matcher with slug '#{matcher.slug}' already registered"
    else
      Agent.update(__MODULE__, fn state ->
        Map.put(state, matcher.slug, matcher)
      end)
    end
  end

  @doc """
  Registers a matcher, replacing any existing matcher with the same slug.

  Unlike `register/1`, this does NOT raise if the slug already exists — it
  silently overwrites. The `!` suffix here signals force-replace intent, not
  raise-on-error (which is the more common Elixir convention). Use this for
  re-loading built-in matchers or hot-reloading custom matchers.

  ## Parameters
  - matcher: A Matcher struct

  ## Returns
  :ok
  """
  def register!(%Matcher{} = matcher) do
    Agent.update(__MODULE__, fn state ->
      Map.put(state, matcher.slug, matcher)
    end)
  end

  @doc """
  Gets a matcher by slug.

  ## Returns
  {:ok, matcher} or :error if not found
  """
  def get(slug) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, slug) do
        nil -> :error
        matcher -> {:ok, matcher}
      end
    end)
  end

  @doc """
  Gets a matcher by slug, raising if not found.

  ## Returns
  matcher or raises if not found
  """
  def get!(slug) do
    case get(slug) do
      {:ok, matcher} -> matcher
      :error -> raise "Matcher with slug '#{slug}' not found"
    end
  end

  @doc """
  Returns all registered matchers.

  ## Returns
  List of Matcher structs
  """
  def all do
    Agent.get(__MODULE__, fn state ->
      Map.values(state)
    end)
  end

  @doc """
  Returns matchers sorted by noise tier priority.

  ## Returns
  List of Matcher structs sorted by tier (precise → normal → noisy)
  """
  def all_sorted do
    all()
    |> Enum.sort_by(&Matcher.tier_priority(&1.noise_tier))
  end

  @doc """
  Returns matchers that match a given file path.

  ## Parameters
  - file_path: Path to the file

  ## Returns
  List of Matcher structs that could match the file
  """
  def for_file(file_path) do
    all()
    |> Enum.filter(fn matcher ->
      Enum.any?(matcher.file_patterns, fn pattern ->
        matches_glob?(file_path, pattern)
      end)
    end)
    |> Enum.sort_by(&Matcher.tier_priority(&1.noise_tier))
  rescue
    _ -> []
  catch
    # The Agent process may not be started (e.g. matcher_system enabled without the
    # Registry supervised). Agent.get/2 then exits with :noproc, which `rescue` does NOT
    # catch — only `catch :exit` does. Degrade to no matchers instead of crashing the scan.
    :exit, _ -> []
  end

  defp matches_glob?(file_path, pattern) do
    # Simplified glob matching for common patterns
    cond do
      # Handle **/*.ext patterns - match any file ending with .ext
      pattern == "**/*" ->
        true

      pattern == "**/*.ex" ->
        String.ends_with?(file_path, ".ex")

      pattern == "**/*.js" ->
        String.ends_with?(file_path, ".js")

      pattern == "**/*.ts" ->
        String.ends_with?(file_path, ".ts")

      pattern == "**/*.py" ->
        String.ends_with?(file_path, ".py")

      pattern == "**/*.rb" ->
        String.ends_with?(file_path, ".rb")

      pattern == "**/*.go" ->
        String.ends_with?(file_path, ".go")

      pattern == "**/*.html" ->
        String.ends_with?(file_path, ".html")

      pattern == "**/*.jsx" ->
        String.ends_with?(file_path, ".jsx")

      pattern == "**/*.tsx" ->
        String.ends_with?(file_path, ".tsx")

      # Handle **/dir/*.ext patterns
      String.contains?(pattern, "**/") ->
        # Extract the suffix after **/
        suffix = String.replace_leading(pattern, "**/", "")
        String.ends_with?(file_path, suffix)

      # Handle *.ext patterns
      String.starts_with?(pattern, "*") ->
        suffix = String.replace_leading(pattern, "*", "")
        String.ends_with?(file_path, suffix)

      # Handle *ext patterns (no dot)
      String.contains?(pattern, "*") ->
        [prefix, suffix] = String.split(pattern, "*")
        String.starts_with?(file_path, prefix) and String.ends_with?(file_path, suffix)

      # Exact match or suffix match
      true ->
        String.ends_with?(file_path, pattern) or file_path == pattern
    end
  end

  @doc """
  Clears all registered matchers.

  ## Returns
  :ok
  """
  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  @doc """
  Removes a matcher by slug.

  ## Returns
  :ok or :error if not found
  """
  def remove(slug) do
    Agent.update(__MODULE__, fn state ->
      if Map.has_key?(state, slug) do
        {_, new_state} = Map.pop(state, slug)
        new_state
      else
        state
      end
    end)
  end

  @doc """
  Returns the count of registered matchers.
  """
  def count do
    Agent.get(__MODULE__, fn state ->
      map_size(state)
    end)
  end

  @doc """
  Loads built-in security matchers.
  """
  def load_built_ins do
    # Clear existing matchers
    clear()

    # Register built-in security matchers
    register_built_in_security_matchers()

    :ok
  end

  # Private functions

  defp register_built_in_security_matchers do
    # SQL Injection patterns
    register!(
      Matcher.new(
        "sql-injection-raw-query",
        :precise,
        ["**/*.ex", "**/*.js", "**/*.ts", "**/*.py", "**/*.rb", "**/*.go"],
        [
          ~r/query_raw\(/,
          ~r/execute\s*\(\s*["'].*\$/,
          ~r/db\.execute\s*\(\s*["'].*\#\{/
        ],
        "Raw SQL query with potential injection"
      )
    )

    # Command injection patterns
    register!(
      Matcher.new(
        "command-injection-shell",
        :precise,
        ["**/*.ex", "**/*.js", "**/*.ts", "**/*.py", "**/*.rb"],
        [
          ~r/System\.cmd\s*\(\s*["'].*\$/,
          ~r/exec\s*\(\s*["'].*\$/,
          ~r/os\.system\s*\(\s*["'].*\$/,
          ~r/spawn\s*\(\s*["'].*\#/
        ],
        "Command execution with user input"
      )
    )

    # Path traversal patterns
    register!(
      Matcher.new(
        "path-traversal",
        :normal,
        ["**/*.ex", "**/*.js", "**/*.ts", "**/*.py", "**/*.rb"],
        [
          ~r/\.\.\/|\.\\.\\/,
          ~r/file:\/\/.*\.\./,
          ~r/readFile\s*\(\s*["'].*\.\./
        ],
        "Path traversal attempt",
        category: "security",
        severity: "high"
      )
    )

    # Hardcoded secrets patterns
    register!(
      Matcher.new(
        "hardcoded-api-key",
        :precise,
        ["**/*.ex", "**/*.js", "**/*.ts", "**/*.py", "**/*.rb", "**/*.go"],
        [
          ~r/api[_-]?key\s*[:=]\s*["']([a-zA-Z0-9]{20,})["']/,
          ~r/secret[_-]?key\s*[:=]\s*["']([a-zA-Z0-9]{20,})["']/,
          ~r/password\s*[:=]\s*["']([a-zA-Z0-9]{8,})["']/
        ],
        "Hardcoded API key or secret",
        category: "security",
        severity: "critical"
      )
    )

    # XSS patterns
    register!(
      Matcher.new(
        "xss-vulnerability",
        :normal,
        ["**/*.ex", "**/*.js", "**/*.ts", "**/*.html", "**/*.jsx", "**/*.tsx"],
        [
          ~r/innerHTML\s*=\s*.*\$/,
          ~r/dangerouslySetInnerHTML/,
          ~r/html\.safe/
        ],
        "Potential XSS vulnerability",
        category: "security",
        severity: "high"
      )
    )

    # Debug/development patterns
    register!(
      Matcher.new(
        "debug-flag-enabled",
        :normal,
        ["**/*.ex", "**/*.js", "**/*.ts", "**/*.py", "**/*.rb"],
        [
          ~r/debug\s*[:=]\s*true/,
          ~r/DEBUG\s*[:=]\s*true/,
          ~r/\bconsole\.log\b/,
          ~r/IO\.inspect/
        ],
        "Debug flag or console output",
        category: "quality",
        severity: "low"
      )
    )

    :ok
  end
end
