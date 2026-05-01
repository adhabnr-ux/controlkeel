defmodule ControlKeel.Analytics.ToolPatternAnalyzer do
  @moduledoc """
  Detects wasteful tool-call sequences from Invocation records and returns
  actionable cost-reduction suggestions.

  Patterns (adapted from WozCode baseline scanner for CK's cross-host tool names):
  - read_batch   — 3+ consecutive read calls with no other tool between them
  - edit_batch   — 3+ consecutive write/edit calls in a single task window
  - grep_read    — search/grep followed within 3 invocations by a read
  - glob_read    — glob/find followed within 3 invocations by a read
  - failed_edit  — write/edit with decision=blocked, then read, then another write/edit
  - bash_sql     — 2+ Bash/shell calls within a 5-turn window that match SQL CLI patterns

  Tool names are normalized across hosts:
  - Claude Code / Codex CLI  : Read, Write, Edit, MultiEdit, Grep, Glob, Bash
  - CK FS tools              : ck_fs_read, ck_fs_grep, ck_fs_find, ck_fs_ls
  - Cursor / Kiro / Windsurf : read_file, write_file, replace_in_file, search, list_directory
  - OpenCode                 : readFile, writeFile, searchFiles, runCommand
  - Cline / Roo              : read_file, write_to_file, search_files, execute_command
  - Devin terminal           : read_file, write_file, run_terminal_command, run_bash, search_code
  - Augment                  : str-replace-editor, save-file, launch-process, search
  - Goose / Hermes / Kilo    : shell, read_file, write_file, search_files
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Mission.Invocation
  alias ControlKeel.Repo

  @read_batch_threshold 3
  @edit_batch_threshold 3
  @grep_read_window 3
  @glob_read_window 3
  @bash_sql_window 5

  # ── Cross-host tool name sets ─────────────────────────────────────────────

  @read_tools ~w(
    Read ck_fs_read
    read_file readFile read_files
    str-replace-editor
  )

  @write_tools ~w(
    Write Edit MultiEdit
    write_file writeFile replace_in_file write_to_file
    str-replace-editor save-file
    apply_diff
  )

  @grep_tools ~w(
    Grep ck_fs_grep
    search searchFiles search_files search_code
    grep find_in_files ripgrep
  )

  @glob_tools ~w(
    Glob ck_fs_find ck_fs_ls
    list_directory listFiles list_files ls
  )

  @bash_tools ~w(
    Bash
    run_command runCommand run_terminal_command run_bash
    launch-process execute_command shell terminal
    run_shell bash_tool
  )

  # Patterns in Bash/shell tool inputs that indicate SQL CLI usage
  @sql_regex ~r/\b(psql|sqlite3|mysql|mariadb|duckdb|clickhouse|DATABASE_URL|PG_|PGHOST)\b/i

  @type pattern ::
          :read_batch
          | :edit_batch
          | :grep_read
          | :glob_read
          | :failed_edit
          | :bash_sql

  @spec analyze(integer()) :: {:ok, [map()]}
  def analyze(session_id) when is_integer(session_id) do
    invocations =
      Invocation
      |> where([i], i.session_id == ^session_id)
      |> order_by([i], asc: i.inserted_at)
      |> select([i], %{
        tool: i.tool,
        decision: i.decision,
        task_id: i.task_id,
        metadata: i.metadata
      })
      |> Repo.all()

    suggestions =
      []
      |> detect_read_batch(invocations)
      |> detect_edit_batch(invocations)
      |> detect_grep_read(invocations)
      |> detect_glob_read(invocations)
      |> detect_failed_edit(invocations)
      |> detect_bash_sql(invocations)

    {:ok, suggestions}
  end

  def analyze(_), do: {:ok, []}

  # ── Pattern detectors ─────────────────────────────────────────────────────

  defp detect_read_batch(suggestions, invocations) do
    count = consecutive_run_max(invocations, &read_tool?/1)

    if count >= @read_batch_threshold do
      [
        %{
          type: :tool_pattern,
          pattern: :read_batch,
          priority: :high,
          title: "Batch file reads — use ck_fs_grep or search first",
          description:
            "Found #{count} consecutive read calls in this session. " <>
              "Use ck_fs_grep (Claude Code/Codex) or the search tool (Cursor/Kiro/Cline) to " <>
              "locate relevant content first, then read only the files you need. " <>
              "This reduces round-trips and context size.",
          call_count: count
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp detect_edit_batch(suggestions, invocations) do
    count = consecutive_run_max(invocations, &write_tool?/1)

    if count >= @edit_batch_threshold do
      [
        %{
          type: :tool_pattern,
          pattern: :edit_batch,
          priority: :high,
          title: "Batch file edits into fewer write calls",
          description:
            "Found #{count} consecutive write/edit calls in this session. " <>
              "Prepare all changes and apply them in as few write calls as possible. " <>
              "Each call carries full context overhead regardless of host.",
          call_count: count
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp detect_grep_read(suggestions, invocations) do
    count = count_followed_by(invocations, &grep_tool?/1, &read_tool?/1, @grep_read_window)

    if count > 0 do
      [
        %{
          type: :tool_pattern,
          pattern: :grep_read,
          priority: :medium,
          title: "Combine search + read — search results already contain content",
          description:
            "Found #{count} search/grep call(s) followed by a read within #{@grep_read_window} turns. " <>
              "Search tools (ck_fs_grep, Grep, search, search_files) return content snippets — " <>
              "avoid the follow-up read unless you need the full file.",
          occurrence_count: count
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp detect_glob_read(suggestions, invocations) do
    count = count_followed_by(invocations, &glob_tool?/1, &read_tool?/1, @glob_read_window)

    if count > 0 do
      [
        %{
          type: :tool_pattern,
          pattern: :glob_read,
          priority: :medium,
          title: "Combine glob/find + read — filter before reading",
          description:
            "Found #{count} glob/find/list call(s) followed by a read within #{@glob_read_window} turns. " <>
              "Use a search tool with a path pattern (ck_fs_grep, search_files) to " <>
              "find and read in one step when possible.",
          occurrence_count: count
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp detect_failed_edit(suggestions, invocations) do
    count = count_failed_edit_pattern(invocations)

    if count > 0 do
      [
        %{
          type: :tool_pattern,
          pattern: :failed_edit,
          priority: :high,
          title: "Failed write → read → retry — read before writing",
          description:
            "Found #{count} blocked write call(s) followed by a read then another write. " <>
              "Read the target file before writing to avoid the retry cycle. " <>
              "Each failed round-trip wastes at least 2 extra context-carrying calls.",
          occurrence_count: count
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  defp detect_bash_sql(suggestions, invocations) do
    count = count_bash_sql_pairs(invocations)

    if count > 0 do
      [
        %{
          type: :tool_pattern,
          pattern: :bash_sql,
          priority: :medium,
          title: "Multiple SQL CLI calls via shell — consolidate queries",
          description:
            "Found #{count} window(s) with 2+ shell calls matching SQL CLI patterns " <>
              "(psql, sqlite3, mysql, duckdb) within #{@bash_sql_window} turns. " <>
              "Consolidate into a single query or a SQL script to avoid repeated " <>
              "subprocess overhead and full context re-sends.",
          occurrence_count: count
        }
        | suggestions
      ]
    else
      suggestions
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp consecutive_run_max(invocations, pred) do
    invocations
    |> Enum.reduce({0, 0}, fn inv, {max_run, cur_run} ->
      if pred.(inv) do
        new_cur = cur_run + 1
        {max(max_run, new_cur), new_cur}
      else
        {max_run, 0}
      end
    end)
    |> elem(0)
  end

  defp count_followed_by(invocations, pred_a, pred_b, window) do
    invocations
    |> Enum.with_index()
    |> Enum.count(fn {inv, idx} ->
      if pred_a.(inv) do
        invocations
        |> Enum.slice((idx + 1)..(idx + window))
        |> Enum.any?(pred_b)
      else
        false
      end
    end)
  end

  defp count_failed_edit_pattern(invocations) do
    indexed = Enum.with_index(invocations)

    Enum.count(indexed, fn {inv, idx} ->
      write_tool?(inv) and blocked?(inv) and
        invocations
        |> Enum.slice((idx + 1)..(idx + @grep_read_window))
        |> has_sequence?(&read_tool?/1, &write_tool?/1)
    end)
  end

  defp count_bash_sql_pairs(invocations) do
    indexed = Enum.with_index(invocations)

    Enum.count(indexed, fn {inv, idx} ->
      if bash_tool?(inv) and sql_command?(inv) do
        window =
          invocations
          |> Enum.slice((idx + 1)..(idx + @bash_sql_window))

        Enum.any?(window, fn w -> bash_tool?(w) and sql_command?(w) end)
      else
        false
      end
    end)
  end

  defp has_sequence?(list, pred_a, pred_b) do
    case Enum.find_index(list, pred_a) do
      nil ->
        false

      a_idx ->
        list
        |> Enum.slice((a_idx + 1)..-1//1)
        |> Enum.any?(pred_b)
    end
  end

  defp sql_command?(%{metadata: meta}) when is_map(meta) do
    command = get_in(meta, ["command"]) || get_in(meta, ["input", "command"]) || ""
    Regex.match?(@sql_regex, command)
  end

  defp sql_command?(_), do: false

  defp read_tool?(%{tool: tool}), do: tool in @read_tools
  defp write_tool?(%{tool: tool}), do: tool in @write_tools
  defp grep_tool?(%{tool: tool}), do: tool in @grep_tools
  defp glob_tool?(%{tool: tool}), do: tool in @glob_tools
  defp bash_tool?(%{tool: tool}), do: tool in @bash_tools
  defp blocked?(%{decision: decision}), do: decision in ~w(blocked reject)
end
