defmodule ControlKeel.MCP.ToolGroupTracker do
  @moduledoc """
  Tracks tool usage to enable adaptive tool group selection.
  Learns which tools are actually used per project and suggests optimal groups.
  """

  use GenServer
  require Logger

  @table_name :tool_group_usage
  # 7 days
  @retention_period :timer.hours(24 * 7)

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def track_tool_usage(project_root, tool_name) do
    GenServer.cast(__MODULE__, {:track_usage, project_root, tool_name})
  end

  def suggest_groups(project_root) do
    GenServer.call(__MODULE__, {:suggest_groups, project_root})
  end

  def reset_project(project_root) do
    GenServer.cast(__MODULE__, {:reset_project, project_root})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :public, :set, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{cleanup_ref: nil}}
  end

  @impl true
  def handle_cast({:track_usage, project_root, tool_name}, state) do
    key = usage_key(project_root, tool_name)
    now = System.system_time(:second)

    # Increment count if key exists, otherwise insert with count 1
    case :ets.lookup(@table_name, key) do
      [{^key, _ts, count}] ->
        :ets.insert(@table_name, {key, now, count + 1})

      [] ->
        :ets.insert(@table_name, {key, now, 1})
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:reset_project, project_root}, state) do
    project_root
    |> project_entries()
    |> Enum.each(fn {key, _timestamp, _count} -> :ets.delete(@table_name, key) end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:get_stats, project_root}, _from, state) do
    stats = collect_usage_stats(project_root)
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:suggest_groups, project_root}, _from, state) do
    groups = suggest_optimal_groups(project_root)
    {:reply, groups, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp usage_key(project_root, tool_name) do
    "#{project_root}:#{tool_name}"
  end

  defp project_entries(project_root) do
    prefix = project_root <> ":"

    @table_name
    |> :ets.tab2list()
    |> Enum.filter(fn
      {key, _timestamp, _count} when is_binary(key) -> String.starts_with?(key, prefix)
      _entry -> false
    end)
  end

  defp collect_usage_stats(project_root) do
    entries = project_entries(project_root)

    if entries == [] do
      %{total_calls: 0, unique_tools: 0}
    else
      total_calls = entries |> Enum.map(fn {_key, _ts, count} -> count end) |> Enum.sum()

      unique_tools =
        entries |> Enum.map(fn {key, _ts, _count} -> key end) |> Enum.uniq() |> length()

      %{total_calls: total_calls, unique_tools: unique_tools}
    end
  end

  defp suggest_optimal_groups(project_root) do
    used_tools =
      project_entries(project_root)
      |> Enum.map(fn {key, _timestamp, _count} ->
        # Extract tool name from "project_root:tool_name" key
        String.replace_prefix(key, project_root <> ":", "")
      end)
      |> Enum.uniq()

    # Map used tools to their groups
    tool_to_group = get_tool_to_group_mapping()

    needed_groups =
      used_tools
      |> Enum.flat_map(fn tool ->
        Map.get(tool_to_group, tool, [])
      end)
      |> Enum.uniq()

    # Always include core + governance as baseline
    baseline_groups = ["core", "governance"]
    suggested_groups = Enum.uniq(baseline_groups ++ needed_groups)

    %{
      suggested: suggested_groups,
      reason: "Based on #{length(used_tools)} unique tools used in this project",
      usage_stats: collect_usage_stats(project_root)
    }
  end

  defp get_tool_to_group_mapping do
    # This should match the groups in protocol.ex
    %{
      # Core
      "ck_validate" => ["core"],
      "ck_context" => ["core"],
      "ck_context_pack" => ["core"],
      "ck_execute_code" => ["core"],
      "ck_budget" => ["core"],
      "ck_route" => ["core"],
      "ck_mcp_discover" => ["core"],
      "ck_token_audit" => ["core"],
      # Governance
      "ck_review_submit" => ["governance"],
      "ck_review_status" => ["governance"],
      "ck_review_feedback" => ["governance"],
      "ck_regression_result" => ["governance"],
      "ck_finding" => ["governance"],
      "ck_goal" => ["governance"],
      "ck_memory_record" => ["governance"],
      "ck_memory_search" => ["governance"],
      "ck_memory_archive" => ["governance"],
      "ck_delegate" => ["governance"],
      "ck_cost_optimizer" => ["governance"],
      "ck_deployment_advisor" => ["governance"],
      "ck_outcome_tracker" => ["governance"],
      # Observability
      "ck_observability" => ["observability"],
      "ck_experience_index" => ["observability"],
      "ck_experience_read" => ["observability"],
      "ck_experience_search" => ["observability"],
      "ck_trace_packet" => ["observability"],
      "ck_failure_clusters" => ["observability"],
      "ck_monitor_subscribe" => ["observability"],
      "ck_tool_health" => ["observability"],
      "ck_skill_evolution" => ["observability"],
      # Skills
      "ck_skill_list" => ["skills"],
      "ck_skill_load" => ["skills"],
      "ck_skill_validate" => ["skills"],
      "ck_load_resources" => ["skills"],
      # Filesystem
      "ck_fs_ls" => ["filesystem"],
      "ck_fs_read" => ["filesystem"],
      "ck_fs_find" => ["filesystem"],
      "ck_fs_grep" => ["filesystem"],
      # Git
      "ck_git_status" => ["git"],
      "ck_git_diff" => ["git"],
      "ck_git_commit" => ["git"],
      # Checkpoints
      "ck_checkpoint_create" => ["checkpoints"],
      "ck_checkpoint_restore" => ["checkpoints"],
      "ck_checkpoint_list" => ["checkpoints"],
      # Worktrees
      "ck_worktree_list" => ["worktrees"],
      "ck_worktree_switch" => ["worktrees"]
    }
  end

  defp cleanup_old_entries do
    cutoff = System.system_time(:second) - @retention_period

    :ets.select_delete(@table_name, [
      {{:_, :"$1", :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, :timer.hours(1))
  end
end
