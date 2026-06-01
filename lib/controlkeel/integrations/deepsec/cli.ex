defmodule ControlKeel.Integrations.Deepsec.CLI do
  @moduledoc """
  CLI interface for deepsec operations.

  This module provides functions to execute deepsec CLI commands
  for scanning, processing, and exporting findings.

  Binary resolution:
  - Default: looks for `deepsec` on PATH
  - Override: `CONTROLKEEL_DEEPSEC_BIN` env var or `deepsec_bin` in Proxy config
  - npx mode: set to "npx" to run via `npx -y deepsec`
  """

  alias ControlKeel.Integrations.Deepsec.Config
  alias ControlKeel.Proxy

  @doc """
  Initializes deepsec in the current directory.
  """
  def init(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    case File.exists?(workspace_path) do
      true ->
        {:ok, "Deepsec already initialized at #{workspace_path}"}

      false ->
        with :ok <- File.mkdir_p(workspace_path) do
          {bin, args} = resolve_command(["init"])

          case safe_cmd(bin, args, cd: workspace_path) do
            {output, 0} -> {:ok, output}
            {output, _} -> {:error, output}
          end
        else
          {:error, reason} -> {:error, "Failed to create deepsec workspace: #{inspect(reason)}"}
        end
    end
  end

  @doc """
  Runs deepsec scan to find candidate sites with regex matchers.
  """
  def scan(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    if File.exists?(workspace_path) do
      {bin, args} = resolve_command(["scan"])

      case safe_cmd(bin, args, cd: workspace_path) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Runs AI investigation on scan results.
  """
  def process(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    if File.exists?(workspace_path) do
      {bin, args} = resolve_command(["process"])

      case safe_cmd(bin, args, cd: workspace_path) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Revalidates existing findings to reduce false positives.
  """
  def revalidate(opts \\ []) do
    workspace_path = Keyword.get(opts, :workspace_path) || Config.workspace_path()

    if File.exists?(workspace_path) do
      {bin, args} = resolve_command(["revalidate"])

      case safe_cmd(bin, args, cd: workspace_path) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Exports findings in the specified format.
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

      {bin, args} = resolve_command(["export", "--format", format_str, "--out", output_path])

      case safe_cmd(bin, args, cd: workspace_path) do
        {output, 0} -> {:ok, output}
        {output, _} -> {:error, output}
      end
    else
      {:error, "Deepsec not initialized. Run init first."}
    end
  end

  @doc """
  Checks if deepsec CLI is available in the system.

  Checks binary existence without running a potentially slow download.
  Returns true if the binary path resolves, false otherwise.
  """
  def available? do
    {bin, _args} = resolve_command(["--version"])
    System.find_executable(bin) != nil
  end

  @doc """
  Gets the deepsec version.
  """
  def version do
    {bin, args} = resolve_command(["--version"])

    case safe_cmd(bin, args) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, _} -> {:error, output}
    end
  end

  @doc """
  Parses JSON output from deepsec commands.
  """
  def parse_json_output(output) do
    try do
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
        extract_findings_from_text(output)
    end
  end

  # Resolves the configured deepsec binary and builds the full argument list.
  # If configured as "npx", returns {"npx", ["-y", "deepsec" | sub_args]}.
  # Otherwise returns the binary path with sub_args directly.
  defp resolve_command(sub_args) do
    configured = Proxy.deepsec_bin()

    if configured == "npx" do
      bin = System.find_executable("npx") || "npx"
      {bin, ["-y", "deepsec" | sub_args]}
    else
      bin = System.find_executable(configured) || configured
      {bin, sub_args}
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

  # Safely execute System.cmd, catching :enoent errors when command is not found
  defp safe_cmd(command, args, opts \\ []) do
    opts = Keyword.put(opts, :stderr_to_stdout, true)

    case Keyword.get(opts, :cd) do
      nil ->
        :ok

      dir ->
        if File.exists?(dir), do: :ok, else: {:error, {:enoent, dir}}
    end
    |> case do
      :ok ->
        try do
          System.cmd(command, args, opts)
        rescue
          _e in [ErlangError] ->
            {"Command not found: #{command}", 127}
        end

      {:error, {:enoent, dir}} ->
        {"Directory not found: #{dir}", 1}
    end
  end
end
