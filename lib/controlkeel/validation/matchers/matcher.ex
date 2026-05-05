defmodule ControlKeel.Validation.Matchers.Matcher do
  @moduledoc """
  Matcher data structure for pattern-based validation.

  Based on deepsec's matcher architecture, this module defines
  the data structure for security pattern matchers with noise tiers.
  """

  @type noise_tier :: :precise | :normal | :noisy
  @type file_pattern :: String.t()
  @type regex_pattern :: Regex.t() | String.t()

  @type t :: %__MODULE__{
          slug: String.t(),
          noise_tier: noise_tier(),
          file_patterns: [file_pattern()],
          regex_patterns: [regex_pattern()],
          description: String.t(),
          category: String.t() | nil,
          severity: String.t() | nil,
          metadata: map()
        }

  defstruct [
    :slug,
    :noise_tier,
    :file_patterns,
    :regex_patterns,
    :description,
    :category,
    :severity,
    metadata: %{}
  ]

  @doc """
  Creates a new matcher.

  ## Parameters
  - slug: Unique identifier for the matcher (kebab-case)
  - noise_tier: :precise, :normal, or :noisy
  - file_patterns: List of glob patterns to match files
  - regex_patterns: List of regex patterns to match content
  - description: Human-readable description
  - opts: Optional keyword arguments
    - category: Finding category (default: "security")
    - severity: Default severity (default: "medium")
    - metadata: Additional metadata

  ## Examples
      iex> Matcher.new("sql-injection", :precise, ["**/*.ex"], [~r/query_raw/], "SQL injection")
      %Matcher{slug: "sql-injection", noise_tier: :precise, ...}
  """
  def new(slug, noise_tier, file_patterns, regex_patterns, description, opts \\ []) do
    %__MODULE__{
      slug: slug,
      noise_tier: validate_noise_tier!(noise_tier),
      file_patterns: List.wrap(file_patterns),
      regex_patterns: compile_regexes(List.wrap(regex_patterns)),
      description: description,
      category: Keyword.get(opts, :category, "security"),
      severity: Keyword.get(opts, :severity, "medium"),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Checks if a matcher matches a given file and content.

  ## Parameters
  - matcher: The matcher to check
  - file_path: Path to the file
  - content: File content

  ## Returns
  {:ok, matches} if the matcher matches, :error if no match
  """
  def matches?(%__MODULE__{} = matcher, file_path, content) do
    with {:ok, _} <- matches_file_pattern?(matcher, file_path),
         {:ok, matches} <- matches_content?(matcher, content) do
      {:ok, matches}
    else
      :error -> :error
    end
  end

  @doc """
  Returns the priority order for noise tiers.
  Precise matchers should be processed first, then normal, then noisy.
  """
  def tier_priority(:precise), do: 0
  def tier_priority(:normal), do: 1
  def tier_priority(:noisy), do: 2

  # Private functions

  defp validate_noise_tier!(tier) when tier in [:precise, :normal, :noisy], do: tier
  defp validate_noise_tier!(tier), do: raise("Invalid noise tier: #{inspect(tier)}")

  defp compile_regexes(patterns) do
    Enum.map(patterns, fn pattern ->
      cond do
        is_binary(pattern) -> Regex.compile!(pattern)
        is_struct(pattern, Regex) -> pattern
        true -> raise("Invalid regex pattern: #{inspect(pattern)}")
      end
    end)
  end

  defp matches_file_pattern?(%__MODULE__{file_patterns: patterns}, file_path) do
    if Enum.any?(patterns, fn pattern -> matches_glob?(file_path, pattern) end) do
      {:ok, :file_match}
    else
      :error
    end
  rescue
    _ -> :error
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

  defp matches_content?(%__MODULE__{regex_patterns: patterns}, content) do
    matches =
      Enum.flat_map(patterns, fn pattern ->
        Regex.scan(pattern, content, return: :index)
      end)

    if matches == [] do
      :error
    else
      {:ok, matches}
    end
  end
end
