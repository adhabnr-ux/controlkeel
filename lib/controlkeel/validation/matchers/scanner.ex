defmodule ControlKeel.Validation.Matchers.Scanner do
  @moduledoc """
  Scanner that uses matchers to detect security patterns.

  This module integrates with ControlKeel's validation system
  to run matchers against file content and generate findings.
  """

  alias ControlKeel.Integrations.Deepsec.{Adapter, CLI}
  alias ControlKeel.Scanner.Finding
  alias ControlKeel.Validation.Matchers.{Matcher, Registry}

  @doc """
  Scans content using registered matchers.

  ## Parameters
  - content: File content to scan
  - file_path: Path to the file (for pattern matching)
  - opts: Optional parameters
    - session_id: Session ID for finding metadata
    - task_id: Task ID for finding metadata
    - max_findings: Maximum number of findings to return (default: 100)

  ## Returns
  List of Finding structs
  """
  def scan(content, file_path, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    task_id = Keyword.get(opts, :task_id)
    max_findings = Keyword.get(opts, :max_findings, 100)

    # Get matchers that could match this file
    matchers = Registry.for_file(file_path)

    # Run matchers and generate findings
    matchers
    |> Enum.flat_map(fn matcher ->
      case Matcher.matches?(matcher, file_path, content) do
        {:ok, matches} ->
          Enum.map(matches, fn match ->
            build_finding(matcher, match, file_path, session_id, task_id)
          end)

        :error ->
          []
      end
    end)
    |> Enum.take(max_findings)
  end

  @doc """
  Scans content using specific matchers by slug.

  ## Parameters
  - content: File content to scan
  - file_path: Path to the file
  - matcher_slugs: List of matcher slugs to use
  - opts: Optional parameters (same as scan/3)

  ## Returns
  List of Finding structs
  """
  def scan_with_matchers(content, file_path, matcher_slugs, opts \\ []) do
    session_id = Keyword.get(opts, :session_id)
    task_id = Keyword.get(opts, :task_id)

    matchers =
      matcher_slugs
      |> Enum.map(&Registry.get/1)
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, matcher} -> matcher end)

    matchers
    |> Enum.flat_map(fn matcher ->
      case Matcher.matches?(matcher, file_path, content) do
        {:ok, matches} ->
          Enum.map(matches, fn match ->
            build_finding(matcher, match, file_path, session_id, task_id)
          end)

        :error ->
          []
      end
    end)
  end

  @doc """
  Returns statistics about the matcher registry.

  ## Returns
  Map with matcher statistics
  """
  def statistics do
    matchers = Registry.all()

    %{
      total_matchers: length(matchers),
      by_tier:
        Enum.group_by(matchers, & &1.noise_tier) |> Map.new(fn {k, v} -> {k, length(v)} end),
      by_category:
        Enum.group_by(matchers, & &1.category) |> Map.new(fn {k, v} -> {k, length(v)} end)
    }
  end

  @doc """
  Runs a deepsec CLI scan and converts results to CK findings.

  This function executes deepsec's scan command (regex-based pattern matching)
  and converts the findings to ControlKeel's finding format.

  ## Parameters
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)
    - session_id: Session ID for finding metadata
    - task_id: Task ID for finding metadata
    - export_format: Export format (:md_dir or :json, default: :json for parsing)

  ## Returns
  {:ok, findings} on success with list of Finding structs
  {:error, reason} on failure
  """
  def deepsec_scan(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path)
    session_id = Keyword.get(opts, :session_id)
    task_id = Keyword.get(opts, :task_id)
    export_format = Keyword.get(opts, :export_format, :json)

    with :ok <- ensure_deepsec_available(),
         {:ok, _} <- CLI.init(workspace_path: workspace_path),
         {:ok, _scan_output} <- CLI.scan(workspace_path: workspace_path),
         {:ok, _process_output} <- CLI.process(workspace_path: workspace_path),
         {:ok, findings} <-
           export_and_parse_findings(export_format, workspace_path, session_id, task_id) do
      {:ok, findings}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Runs a full deepsec workflow including revalidation.

  ## Parameters
  - opts: Keyword list of options (same as deepsec_scan/1)
    - skip_revalidate: Skip revalidation step (default: false)

  ## Returns
  {:ok, findings} on success with list of Finding structs
  {:error, reason} on failure
  """
  def deepsec_full_scan(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path)
    session_id = Keyword.get(opts, :session_id)
    task_id = Keyword.get(opts, :task_id)
    export_format = Keyword.get(opts, :export_format, :json)

    with :ok <- ensure_deepsec_available(),
         {:ok, _} <- CLI.init(workspace_path: workspace_path),
         {:ok, _scan_output} <- CLI.scan(workspace_path: workspace_path),
         {:ok, _process_output} <- CLI.process(workspace_path: workspace_path),
         {:ok, _revalidate_output} <- maybe_revalidate(opts),
         {:ok, findings} <-
           export_and_parse_findings(export_format, workspace_path, session_id, task_id) do
      {:ok, findings}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp ensure_deepsec_available do
    if CLI.available?() do
      :ok
    else
      {:error, "Deepsec CLI is not available. Please install it with: npm install -g deepsec"}
    end
  end

  defp maybe_revalidate(opts) do
    if Keyword.get(opts, :skip_revalidate, false) do
      {:ok, "Revalidation skipped"}
    else
      CLI.revalidate(workspace_path: Keyword.get(opts, :workspace_path))
    end
  end

  defp export_and_parse_findings(format, workspace_path, session_id, task_id) do
    output_dir =
      System.tmp_dir!() |> Path.join("deepsec_export_#{System.unique_integer([:positive])}")

    result =
      case CLI.export(format, workspace_path: workspace_path, output: output_dir) do
        {:ok, _output} ->
          parse_exported_findings(format, output_dir, session_id, task_id)

        {:error, reason} ->
          {:error, "Failed to export findings: #{reason}"}
      end

    File.rm_rf(output_dir)
    result
  end

  defp parse_exported_findings(:json, output_dir, session_id, task_id) do
    json_file = Path.join([output_dir, "findings.json"])

    case File.read(json_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            findings = Map.get(data, "findings", [])

            ck_findings =
              Adapter.to_ck_findings(findings, session_id: session_id, task_id: task_id)

            {:ok, ck_findings}

          {:error, reason} ->
            {:error, "Failed to parse JSON: #{reason}"}
        end

      {:error, _} ->
        # Try alternative structure
        find_json_files(output_dir)
    end
  end

  defp parse_exported_findings(:md_dir, _output_dir, _session_id, _task_id) do
    # Markdown export produces human-readable reports, not machine-parseable findings.
    # Use :json format when programmatic access to findings is required.
    {:error,
     "Markdown export is not parseable as structured findings. Use format: :json instead."}
  end

  defp find_json_files(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        json_files = Enum.filter(files, &String.ends_with?(&1, ".json"))

        case json_files do
          [] ->
            {:error, "No JSON files found in export directory"}

          [file | _] ->
            parse_json_file(Path.join(dir, file))
        end

      {:error, reason} ->
        {:error, "Failed to list export directory: #{reason}"}
    end
  end

  defp parse_json_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            findings =
              cond do
                is_list(data) -> data
                Map.has_key?(data, "findings") -> Map.get(data, "findings", [])
                true -> []
              end

            {:ok, Adapter.to_ck_findings(findings)}

          {:error, reason} ->
            {:error, "Failed to parse JSON: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to read file: #{reason}"}
    end
  end

  defp build_finding(matcher, match, file_path, session_id, task_id) do
    {line, col} =
      case match do
        {line, col} when is_integer(line) and is_integer(col) -> {line, col}
        {line, _} when is_integer(line) -> {line, 0}
        [{line, col}] when is_integer(line) and is_integer(col) -> {line, col}
        [{line, _}] when is_integer(line) -> {line, 0}
        _ -> {0, 0}
      end

    # Determine decision based on severity
    decision = decision_for_severity(matcher.severity)

    %Finding{
      id: generate_finding_id(matcher.slug, file_path, line),
      severity: matcher.severity,
      category: matcher.category || "security",
      rule_id: "matcher.#{matcher.slug}",
      decision: decision,
      plain_message: "[#{matcher.slug}] #{matcher.description}",
      location: %{
        "path" => file_path,
        "kind" => "code",
        "line" => line,
        "column" => col
      },
      metadata: %{
        "scanner" => "matcher_system",
        "matcher_slug" => matcher.slug,
        "noise_tier" => Atom.to_string(matcher.noise_tier),
        "matcher_description" => matcher.description,
        "session_id" => session_id,
        "task_id" => task_id
      }
    }
  end

  defp decision_for_severity("critical"), do: "block"
  defp decision_for_severity("high"), do: "warn"
  defp decision_for_severity(_), do: "warn"

  defp generate_finding_id(slug, file_path, line) do
    seed = "matcher:#{slug}:#{file_path}:#{line}"
    "mt_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end
end
