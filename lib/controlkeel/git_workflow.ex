defmodule ControlKeel.GitWorkflow do
  @moduledoc """
  Governed git workflow integration with CK validation and review system.
  Provides diff review, commit validation, and status correlation with findings.
  """

  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission

  def diff(project_root, base_ref, head_ref, opts \\ []) do
    # Generate diff
    case System.cmd(
           "git",
           ["diff", base_ref, head_ref],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {diff_output, 0} ->
        # Run validation on diff
        validation_result = validate_diff(diff_output, project_root, opts)

        {:ok,
         %{
           "base_ref" => base_ref,
           "head_ref" => head_ref,
           "diff" => diff_output,
           "validation" => validation_result,
           "files_changed" => count_changed_files(diff_output)
         }}

      {error_output, exit_code} ->
        {:error,
         {:git_error,
          "Git diff failed with exit code #{exit_code}: #{String.slice(error_output, 0, 500)}"}}
    end
  end

  def commit(project_root, message, opts \\ []) do
    # Validate commit message via ck_validate
    case validate_commit_message(message, project_root, opts) do
      {:ok, _validation} ->
        # Check for blocked findings
        case check_blocked_findings(project_root, opts) do
          :ok ->
            commit_args = ["commit", "-m", message]

            case System.cmd("git", commit_args, cd: project_root, stderr_to_stdout: true) do
              {output, 0} ->
                head_sha = get_current_sha(project_root)

                {:ok,
                 %{
                   "message" => "Commit successful",
                   "head_sha" => head_sha,
                   "commit_message" => message,
                   "git_output" => output
                 }}

              {error_output, exit_code} ->
                {:error,
                 {:git_error,
                  "Git commit failed with exit code #{exit_code}: #{String.slice(error_output, 0, 500)}"}}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:validation_error, reason}}
    end
  end

  def status(project_root, opts \\ []) do
    # Get git status
    case System.cmd("git", ["status", "--porcelain"], cd: project_root, stderr_to_stdout: true) do
      {status_output, 0} ->
        # Parse status
        status_info = parse_git_status(status_output)

        # Get current branch and SHA
        branch = get_current_branch(project_root)
        head_sha = get_current_sha(project_root)

        # Correlate with CK findings if session_id is provided
        findings_correlation =
          case Keyword.get(opts, :session_id) do
            nil -> %{"available" => false}
            session_id -> correlate_findings(session_id, project_root)
          end

        {:ok,
         %{
           "branch" => branch,
           "head_sha" => head_sha,
           "status" => status_info,
           "findings_correlation" => findings_correlation
         }}

      {error_output, exit_code} ->
        {:error,
         {:git_error,
          "Git status failed with exit code #{exit_code}: #{String.slice(error_output, 0, 500)}"}}
    end
  end

  # Private functions

  defp validate_diff(diff_output, project_root, opts) do
    # Use ck_validate to check the diff
    validation_args = %{
      "content" => diff_output,
      "kind" => "code",
      "intended_use" => "review",
      "path" => project_root,
      "artifact_type" => "diff"
    }

    validation_args =
      if Keyword.get(opts, :session_id) do
        Map.put(validation_args, "session_id", Keyword.get(opts, :session_id))
      else
        validation_args
      end

    case CkValidate.call(validation_args) do
      {:ok, result} -> result
      {:error, reason} -> %{"error" => inspect(reason), "allowed" => false}
    end
  end

  defp validate_commit_message(message, project_root, opts) do
    # Validate commit message for security context and quality
    validation_args = %{
      "content" => message,
      "kind" => "text",
      "intended_use" => "review",
      "path" => project_root,
      "artifact_type" => "source"
    }

    validation_args =
      if Keyword.get(opts, :session_id) do
        Map.put(validation_args, "session_id", Keyword.get(opts, :session_id))
      else
        validation_args
      end

    case CkValidate.call(validation_args) do
      {:ok, %{"decision" => "block"} = result} -> {:error, result}
      {:ok, result} -> {:ok, result}
      {:error, _reason} -> {:ok, %{"decision" => "allowed", "note" => "validation unavailable"}}
    end
  end

  defp check_blocked_findings(_project_root, opts) do
    case Keyword.get(opts, :session_id) do
      nil ->
        :ok

      session_id ->
        counts = Mission.session_finding_counts(session_id)

        if counts.blocked > 0 or counts.critical_active > 0 do
          {:error,
           {:blocked_findings,
            "Cannot commit: session has #{counts.blocked} blocked and #{counts.critical_active} critical active findings"}}
        else
          :ok
        end
    end
  end

  defp count_changed_files(diff_output) do
    diff_output
    |> String.split("\n")
    |> Enum.count(fn line -> String.starts_with?(line, "diff --git") end)
  end

  defp parse_git_status(status_output) do
    lines = String.split(status_output, "\n", trim: true)

    %{
      "modified" => count_status(lines, ~r/^[AM]./),
      "staged" => count_status(lines, ~r/^[MADRC]./),
      "untracked" => count_status(lines, ~r/^\?\?/),
      "deleted" => count_status(lines, ~r/^.D/),
      "renamed" => count_status(lines, ~r/^R/),
      "total" => length(lines)
    }
  end

  defp count_status(lines, regex) do
    Enum.count(lines, fn line -> Regex.match?(regex, line) end)
  end

  defp get_current_branch(project_root) do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {branch, 0} -> String.trim(branch)
      _ -> "unknown"
    end
  end

  defp get_current_sha(project_root) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: project_root, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      _ -> "unknown"
    end
  end

  defp correlate_findings(session_id, _project_root) do
    counts = Mission.session_finding_counts(session_id)

    %{
      "available" => true,
      "session_id" => session_id,
      "findings_count" => counts.total,
      "active_count" => counts.active,
      "blocked_count" => counts.blocked,
      "critical_active" => counts.critical_active,
      "high_active" => counts.high_active,
      "message" => "Findings correlation available"
    }
  end
end
