defmodule ControlKeel.MCP.ToolGroupTrackerTest do
  use ExUnit.Case, async: false

  alias ControlKeel.MCP.ToolGroupTracker

  setup do
    project_root = Path.join(System.tmp_dir!(), "ck-tool-groups-#{System.unique_integer([:positive])}")

    ToolGroupTracker.reset_project(project_root)
    sync_tracker()

    on_exit(fn ->
      ToolGroupTracker.reset_project(project_root)
      sync_tracker()
    end)

    {:ok, project_root: project_root}
  end

  test "tracks tool usage for a project", %{project_root: project_root} do
    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    sync_tracker()

    %{usage_stats: stats, reason: reason} = ToolGroupTracker.suggest_groups(project_root)

    assert stats.total_calls == 2
    assert stats.unique_tools == 1
    assert reason == "Based on 1 unique tools used in this project"
  end

  test "suggests groups based on observed tools", %{project_root: project_root} do
    ToolGroupTracker.track_tool_usage(project_root, "ck_git_status")
    sync_tracker()

    %{suggested: suggested, usage_stats: stats} = ToolGroupTracker.suggest_groups(project_root)

    assert stats.unique_tools == 1
    assert "core" in suggested
    assert "governance" in suggested
    assert "git" in suggested
  end

  test "reset_project clears only that project's usage", %{project_root: project_root} do
    other_project = project_root <> "-other"

    ToolGroupTracker.track_tool_usage(project_root, "ck_git_status")
    ToolGroupTracker.track_tool_usage(other_project, "ck_fs_read")
    sync_tracker()

    ToolGroupTracker.reset_project(project_root)
    sync_tracker()

    assert %{usage_stats: %{total_calls: 0, unique_tools: 0}} =
             ToolGroupTracker.suggest_groups(project_root)

    assert %{usage_stats: %{total_calls: 1, unique_tools: 1}, suggested: other_suggested} =
             ToolGroupTracker.suggest_groups(other_project)

    assert "filesystem" in other_suggested

    ToolGroupTracker.reset_project(other_project)
  end

  defp sync_tracker do
    _ = :sys.get_state(ToolGroupTracker)
    :ok
  end
end
