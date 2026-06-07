defmodule ControlKeel.MCP.ToolGroupTrackerPersistenceTest do
  use ExUnit.Case, async: false

  alias ControlKeel.MCP.ToolGroupTracker

  setup do
    project_root =
      Path.join(System.tmp_dir!(), "ck-tool-persist-#{System.unique_integer([:positive])}")

    File.mkdir_p!(project_root)

    ToolGroupTracker.reset_project(project_root)
    sync_tracker()

    on_exit(fn ->
      ToolGroupTracker.reset_project(project_root)
      sync_tracker()
      File.rm_rf(Path.join(project_root, ".controlkeel"))
    end)

    {:ok, project_root: project_root}
  end

  test "usage survives simulated restart", %{project_root: project_root} do
    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    ToolGroupTracker.track_tool_usage(project_root, "ck_git_status")
    sync_tracker()

    assert :ok = ToolGroupTracker.flush_to_disk(project_root)

    clear_project_entries(project_root)

    assert {:ok, 2} = ToolGroupTracker.load_from_disk(project_root)

    %{usage_stats: stats} = ToolGroupTracker.suggest_groups(project_root)
    assert stats.total_calls == 3
    assert stats.unique_tools == 2
  end

  test "fresh install with no file works", %{project_root: project_root} do
    assert {:ok, 0} = ToolGroupTracker.load_from_disk(project_root)

    %{usage_stats: stats} = ToolGroupTracker.suggest_groups(project_root)
    assert stats.total_calls == 0
    assert stats.unique_tools == 0
  end

  test "corrupt file is handled gracefully", %{project_root: project_root} do
    dir = Path.join(project_root, ".controlkeel")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "tool_usage.json"), "{not valid json!!!")

    assert {:error, :corrupt} = ToolGroupTracker.load_from_disk(project_root)
  end

  test "flush creates file with correct JSON format", %{project_root: project_root} do
    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    sync_tracker()

    assert :ok = ToolGroupTracker.flush_to_disk(project_root)

    file_path = Path.join([project_root, ".controlkeel", "tool_usage.json"])
    assert File.exists?(file_path)

    {:ok, decoded} = file_path |> File.read!() |> Jason.decode()

    assert decoded["version"] == 1
    assert length(decoded["entries"]) == 1

    [%{"key" => key, "count" => count, "last_used" => last_used}] = decoded["entries"]
    assert String.contains?(key, "ck_validate")
    assert count == 1
    assert is_integer(last_used)
  end

  test "flush creates .controlkeel directory when missing", %{project_root: project_root} do
    ck_dir = Path.join(project_root, ".controlkeel")
    refute File.exists?(ck_dir)

    ToolGroupTracker.track_tool_usage(project_root, "ck_fs_read")
    sync_tracker()

    assert :ok = ToolGroupTracker.flush_to_disk(project_root)
    assert File.exists?(ck_dir)
    assert File.exists?(Path.join(ck_dir, "tool_usage.json"))
  end

  test "load does not overwrite newer ETS data", %{project_root: project_root} do
    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    sync_tracker()

    assert :ok = ToolGroupTracker.flush_to_disk(project_root)

    ToolGroupTracker.track_tool_usage(project_root, "ck_validate")
    sync_tracker()

    %{usage_stats: %{total_calls: before_count}} =
      ToolGroupTracker.suggest_groups(project_root)

    assert {:ok, 1} = ToolGroupTracker.load_from_disk(project_root)

    %{usage_stats: %{total_calls: after_count}} =
      ToolGroupTracker.suggest_groups(project_root)

    assert after_count == before_count
  end

  defp sync_tracker do
    _ = :sys.get_state(ToolGroupTracker)
    :ok
  end

  defp clear_project_entries(project_root) do
    prefix = project_root <> ":"

    :tool_group_usage
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _, _} -> String.starts_with?(key, prefix) end)
    |> Enum.each(fn {key, _, _} -> :ets.delete(:tool_group_usage, key) end)
  end
end
