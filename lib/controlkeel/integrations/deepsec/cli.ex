defmodule ControlKeel.Integrations.Deepsec.CLI do
  @moduledoc """
  CLI interface for deepsec operations.

  This module provides functions to execute deepsec CLI commands
  for scanning, processing, and exporting findings.
  """

  alias ControlKeel.Integrations.Deepsec.Config

  @doc """
  Initializes deepsec in the current directory.

  ## Parameters
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)

  ## Returns
  {:ok, output} on success
  {:error, reason} on failure
  """
  def init(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    case File.exists?(workspace_path) do
      true ->
        {:ok, "Deepsec already initialized at #{workspace_path}"}

      false ->
        # Run npx deepsec init
        case System.cmd("npx", ["deepsec", "init"], cd: workspace_path, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, _} -> {:error, output}
        end
    end
  end

  @doc """
  Runs deepsec scan to find candidate sites with regex matchers.

  ## Parameters
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)

  ## Returns
  {:ok, output} on success
  {:error, reason} on failure
  """
  def scan(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    if File.exists?(workspace_path) do
      case System.cmd("pnpm", ["deepsec", "scan"],
             cd: workspace_path,
             stderr_to_stdout: true
           ) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Runs AI investigation on scan results.

  ## Parameters
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)

  ## Returns
  {:ok, output} on success
  {:error, reason} on failure
  """
  def process(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    if File.exists?(workspace_path) do
      case System.cmd("pnpm", ["deepsec", "process"],
             cd: workspace_path,
             stderr_to_stdout: true
           ) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Revalidates existing findings to reduce false positives.

  ## Parameters
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)

  ## Returns
  {:ok, output} on success
  {:error, reason} on failure
  """
  def revalidate(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    if File.exists?(workspace_path) do
      case System.cmd("pnpm", ["deepsec", "revalidate"],
             cd: workspace_path,
             stderr_to_stdout: true
           ) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Exports findings in the specified format.

  ## Parameters
  - format: Export format (:md_dir, :json)
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)
    - output: Output directory (default: ./findings)

  ## Returns
  {:ok, output} on success
  {:error, reason} on failure
  """
  def export(format, opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()
    output_path = Keyword.get(opts, :output, "./findings")

    if File.exists?(workspace_path) do
      format_str =
        case format do
          :md_dir -> "md-dir"
          :json -> "json"
          _ -> "md-dir"
        end

      case System.cmd("pnpm", ["deepsec", "export", "--format", format_str, "--out", output_path],
             cd: workspace_path,
             stderr_to_stdout: true
           ) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Runs a complete deepsec workflow: scan → process → revalidate → export.

  ## Parameters
  - opts: Keyword list of options
    - workspace_path: Path to deepsec workspace (default from config)
    - skip_revalidate: Skip revalidation step (default: false)
    - export_format: Export format (:md_dir or :json, default: :md_dir)
    - output: Output directory (default: ./findings)

  ## Returns
  {:ok, results} on success with results from each step
  {:error, reason} on failure
  """
  def run_full_workflow(opts \\ []) do
    with {:ok, _} <- init(opts),
         {:ok, scan_output} <- scan(opts),
         {:ok, process_output} <- process(opts),
         {:ok, results} <- maybe_revalidate(opts, scan_output, process_output),
         {:ok, export_output} <- export(Keyword.get(opts, :export_format, :md_dir), opts) do
      {:ok,
       %{
         scan: scan_output,
         process: process_output,
         revalidate: Keyword.get(results, :revalidate),
         export: export_output
       }}
    end
  end

  # Private functions

  defp maybe_revalidate(opts, scan_output, process_output) do
    if Keyword.get(opts, :skip_revalidate, false) do
      {:ok, %{scan: scan_output, process: process_output, revalidate: nil}}
    else
      case revalidate(opts) do
        {:ok, revalidate_output} ->
          {:ok, %{scan: scan_output, process: process_output, revalidate: revalidate_output}}

        {:error, reason} ->
          # Continue even if revalidation fails
          {:ok, %{scan: scan_output, process: process_output, revalidate: "Skipped: #{reason}"}}
      end
    end
  end

  @doc """
  Checks if deepsec CLI is available in the system.

  ## Returns
  true if deepsec CLI is available, false otherwise
  """
  def available? do
    case System.cmd("npx", ["--yes", "deepsec", "--help"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  end

  @doc """
  Gets the deepsec version.

  ## Returns
  {:ok, version} on success
  {:error, reason} on failure
  """
  def version do
    case System.cmd("npx", ["--yes", "deepsec", "--version"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, output}
    end
  end

  @doc """
  Parses JSON output from deepsec commands.

  ## Parameters
  - output: Raw output string from deepsec command

  ## Returns
  {:ok, parsed_data} on success
  {:error, reason} on failure
  """
  def parse_json_output(output) do
    try do
      # Look for JSON objects in the output
      json_pattern = ~r/\{[\s\S]*\}/

      case Regex.run(json_pattern, output) do
        [json_string] ->
          case Jason.decode(json_string) do
            {:ok, data} -> {:ok, data}
            {:error, reason} -> {:error, "JSON parse error: #{inspect(reason)}"}
          end

        _ ->
          {:error, "No JSON found in output"}
      end
    rescue
      e -> {:error, "Parse error: #{inspect(e)}"}
    end
  end

  @doc """
  Extracts findings from deepsec process output.

  ## Parameters
  - output: Raw output string from deepsec process command

  ## Returns
  {:ok, findings} on success with list of finding maps
  {:error, reason} on failure
  """
  def extract_findings(output) do
    case parse_json_output(output) do
      {:ok, data} ->
        findings = Map.get(data, "findings", [])

        if is_list(findings) do
          {:ok, findings}
        else
          {:error, "Invalid findings format in output"}
        end

      {:error, _reason} ->
        # Fallback: try to extract findings from text output
        extract_findings_from_text(output)
    end
  end

  defp extract_findings_from_text(output) do
    lines = String.split(output, "\n")

    findings =
      lines
      |> Enum.filter(fn line ->
        String.contains?(String.downcase(line), "vulnerability") or
          String.contains?(String.downcase(line), "finding") or
          String.contains?(String.downcase(line), "issue")
      end)
      |> Enum.map(fn line ->
        %{
          "type" => "text_extracted",
          "message" => String.trim(line),
          "severity" => infer_severity_from_text(line)
        }
      end)

    {:ok, findings}
  end

  defp infer_severity_from_text(text) do
    text_lower = String.downcase(text)

    cond do
      String.contains?(text_lower, "critical") -> "CRITICAL"
      String.contains?(text_lower, "high") -> "HIGH"
      String.contains?(text_lower, "medium") -> "MEDIUM"
      true -> "LOW"
    end
  end
end
