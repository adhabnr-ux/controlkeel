defmodule ControlKeel.VirtualWorkspaceTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Mission
  alias ControlKeel.VirtualWorkspace

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-virtual-workspace-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "lib"))
    File.mkdir_p!(Path.join(tmp_dir, "test"))
    File.mkdir_p!(Path.join(tmp_dir, "deps/vendor"))

    File.write!(
      Path.join(tmp_dir, "lib/checkpoint_store.ex"),
      "defmodule CheckpointStore do\n  def target, do: :needle\nend\n"
    )

    File.write!(
      Path.join(tmp_dir, "test/checkpoint_store_test.exs"),
      "defmodule CheckpointStoreTest do\n  @needle :needle\nend\n"
    )

    File.write!(
      Path.join(tmp_dir, "deps/vendor/checkpoint_store.ex"),
      "defmodule Vendor.CheckpointStore do\n  @needle :needle\nend\n"
    )

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    workspace_attrs = %{
      name: "Virtual Workspace",
      slug: "virtual-workspace-#{System.unique_integer([:positive])}",
      industry: "software",
      agent: "test",
      budget_cents: 0,
      compliance_profile: "none",
      status: "active"
    }

    assert {:ok, workspace} = Mission.create_workspace(workspace_attrs)

    session_attrs = %{
      title: "Virtual workspace session",
      objective: "Search orientation",
      risk_tier: "low",
      status: "planned",
      budget_cents: 0,
      daily_budget_cents: 0,
      spent_cents: 0,
      execution_brief: %{},
      metadata: %{"runtime_context" => %{"project_root" => tmp_dir}},
      workspace_id: workspace.id
    }

    assert {:ok, session} = Mission.create_session(session_attrs)

    %{session: session}
  end

  test "find ranks source-ish paths first and emits orientation metadata", %{session: session} do
    assert {:ok, result} = VirtualWorkspace.find(session.id, "checkpoint_store", limit: 10)

    [first | rest] = result["matches"]

    assert first["path"] == "lib/checkpoint_store.ex"
    assert first["rank"] == 1
    assert first["orientation_hint"] == "source"
    assert first["path_depth"] == 2
    assert "basename" in first["matched_on"]
    assert is_integer(first["orientation_score"])

    assert Enum.any?(rest, &(&1["orientation_hint"] == "test"))
    assert Enum.any?(rest, &(&1["orientation_hint"] == "vendor"))
  end

  test "grep emits file summaries and per-match orientation metadata", %{session: session} do
    assert {:ok, result} =
             VirtualWorkspace.grep(session.id, "needle", limit: 10, fixed_strings: true)

    assert result["file_count"] == 3
    assert [%{"path" => "lib/checkpoint_store.ex", "rank" => 1} | _] = result["files"]

    assert Enum.all?(result["matches"], &is_integer(&1["rank"]))
    assert Enum.all?(result["matches"], &is_integer(&1["file_match_count"]))
    assert Enum.any?(result["matches"], &(&1["orientation_hint"] == "source"))
  end
end
