defmodule ControlKeel.Git.Workflow do
  @moduledoc """
  Governed git workflow integration with CK validation and review system.
  Provides diff review, commit validation, and status correlation with findings.
  """

  alias ControlKeel.MCP.Tools.CkValidate
  alias ControlKeel.Mission

  require Logger

  # Blocked/critical findings older than this (in days) become dormant in the
  # commit gate: they no longer hard-block but are still surfaced and logged.
  # Configurable via `config :controlkeel, commit_gate: [stale_block_days: N]`;
  # 0 disables dormancy (all blockers gate, the original behavior).
  @default_stale_block_days 90

  def diff(project_root, base_ref, head_ref, opts \\ []) do
    diff_args = diff_args(base_ref, head_ref)

    # Generate diff
    case ControlKeel.Git.cmd(diff_args,
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

            case ControlKeel.Git.cmd(commit_args, cd: project_root, stderr_to_stdout: true) do
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
    case ControlKeel.Git.cmd(["status", "--porcelain"], cd: project_root, stderr_to_stdout: true) do
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

  defp diff_args(nil, nil), do: ["diff", "HEAD"]
  defp diff_args(base_ref, nil), do: ["diff", base_ref]
  defp diff_args(nil, head_ref), do: ["diff", head_ref]
  defp diff_args(base_ref, head_ref), do: ["diff", base_ref, head_ref]

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
        # Fetch the actual blockers (not just counts) so we can apply a staleness
        # policy: findings older than `stale_block_days` become dormant — they no
        # longer hard-block, but are surfaced in the error and logged so they stay
        # visible instead of accumulating as permanent, invisible gates.
        blockers = Mission.blocking_findings_for_session(session_id)
        stale_days = stale_block_days()
        {fresh, stale} = partition_by_age(blockers, stale_days)

        cond do
          fresh != [] ->
            {:error, {:blocked_findings, format_blocked_findings(fresh, stale, stale_days)}}

          stale != [] ->
            Logger.warning(
              "[commit-gate] #{length(stale)} finding(s) older than #{stale_days} day(s) are " <>
                "dormant and did not block this commit. Review and dismiss or re-confirm them."
            )

            :ok

          true ->
            :ok
        end
    end
  end

  # Partition findings into {fresh, stale} by age. A finding is stale when its
  # age in days exceeds `stale_days`. `stale_days` of 0 means never expire (all
  # blockers are fresh), preserving the original behavior.
  defp partition_by_age(findings, stale_days) when is_integer(stale_days) and stale_days > 0 do
    Enum.split_with(findings, fn f -> age_days(f.inserted_at) <= stale_days end)
  end

  defp partition_by_age(findings, _stale_days), do: {findings, []}

  defp age_days(nil), do: 0

  defp age_days(at) when is_struct(at, DateTime) do
    Date.diff(Date.utc_today(), DateTime.to_date(at))
  end

  defp age_days(%Date{} = date), do: Date.diff(Date.utc_today(), date)

  defp age_days(_), do: 0

  defp stale_block_days do
    Application.get_env(:controlkeel, :commit_gate, [])
    |> Keyword.get(:stale_block_days, @default_stale_block_days)
  end

  # Format the blocking findings into a self-describing error so the operator can
  # see exactly what is gating the commit and how to resolve each one, instead of
  # a bare count. Finding bodies/matched-text are intentionally excluded — only
  # id, rule, severity, title, and age are surfaced. Dormant (stale) findings are
  # listed separately so the operator knows they were NOT counted as blockers.
  defp format_blocked_findings(fresh, stale, stale_days) do
    fresh_lines =
      Enum.map(fresh, fn f ->
        "  ##{f.id} [#{f.severity}/#{f.status}] #{f.rule_id} — #{f.title}#{age_label(f.inserted_at)}"
      end)

    summary =
      "Cannot commit: #{length(fresh)} blocking finding(s) gate this commit " <>
        "(staleness threshold: #{stale_days} days)."

    listing =
      "\n\nBlocking findings:\n" <>
        Enum.join(fresh_lines, "\n")

    dormant =
      if stale != [] do
        stale_lines =
          Enum.map(stale, fn f ->
            "  ##{f.id} [#{f.severity}/#{f.status}] #{f.rule_id} — #{f.title}#{age_label(f.inserted_at)}"
          end)

        "\n\nDormant (older than #{stale_days} days, NOT blocking — review and dismiss or re-confirm):\n" <>
          Enum.join(stale_lines, "\n")
      else
        ""
      end

    hint =
      "\n\nResolve each with: controlkeel approve <finding_id>  " <>
        "(or `ck_finding` resolve/dismiss by id)"

    summary <> listing <> dormant <> hint
  end

  defp age_label(nil), do: ""
  defp age_label(%DateTime{} = at), do: age_label(DateTime.to_date(at))

  defp age_label(%Date{} = date) do
    days = Date.diff(Date.utc_today(), date)

    cond do
      days <= 0 -> " (today)"
      days == 1 -> " (1 day old)"
      days < 90 -> " (#{days} days old)"
      true -> " (>#{div(days, 30)} months old)"
    end
  end

  defp age_label(_), do: ""

  defp count_changed_files(diff_output) do
    diff_output
    |> String.split("\n")
    |> Enum.count(fn line -> String.starts_with?(line, "diff --git") end)
  end

  defp parse_git_status(status_output) do
    lines =
      status_output
      |> String.split("\n", trim: true)
      |> Enum.filter(&ControlKeel.Git.porcelain_entry?/1)

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
    case ControlKeel.Git.cmd(["rev-parse", "--abbrev-ref", "HEAD"],
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {branch, 0} -> String.trim(branch)
      _ -> "unknown"
    end
  end

  defp get_current_sha(project_root) do
    case ControlKeel.Git.cmd(["rev-parse", "HEAD"], cd: project_root, stderr_to_stdout: true) do
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
