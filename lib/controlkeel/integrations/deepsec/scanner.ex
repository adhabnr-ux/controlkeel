defmodule ControlKeel.Integrations.Deepsec.Scanner do
  @moduledoc """
  Scanner that integrates with the deepsec CLI for security pattern detection.

  This module provides `deepsec_scan/1`, the production entrypoint for running a
  deepsec scan and returning CK findings. The fast-path scanner calls it only when
  Deepsec is enabled, the artifact is security/code-like, severity passes the
  configured threshold, and the session has enough budget remaining.
  """

  alias ControlKeel.Integrations.Deepsec.{Adapter, CLI}

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

  # Private functions

  defp ensure_deepsec_available do
    if CLI.available?() do
      :ok
    else
      {:error, "Deepsec CLI is not available. Please install it with: npm install -g deepsec"}
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
end
