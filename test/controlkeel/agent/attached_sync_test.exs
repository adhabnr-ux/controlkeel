defmodule ControlKeel.Agent.AttachedSyncTest do
  use ControlKeel.DataCase

  alias ControlKeel.Agent.AttachedSync
  alias ControlKeel.Project.Binding

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-attached-sync-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "sync refreshes stale repo-native attachments to the current CK version", %{
    tmp_dir: tmp_dir
  } do
    current_version = to_string(Application.spec(:controlkeel, :vsn) || "0.2.0")

    binding = %{
      "workspace_id" => 1,
      "session_id" => 1,
      "agent" => "claude",
      "attached_agents" => %{
        "cursor" => %{
          "target" => "cursor-native",
          "scope" => "project",
          "controlkeel_version" => "0.0.1"
        }
      },
      "bootstrap" => %{"mode" => "project", "auto_bootstrapped" => false}
    }

    assert {:ok, written} = Binding.write(binding, tmp_dir)
    assert {:ok, synced, changes} = AttachedSync.sync(written, tmp_dir, mode: :project)

    assert [%{"agent" => "cursor", "status" => "synced"}] = changes
    assert synced["attached_agents"]["cursor"]["controlkeel_version"] == current_version
    assert synced["attached_agents"]["cursor"]["synced_at"]
    assert File.exists?(Path.join(tmp_dir, ".cursor/mcp.json"))
    assert File.exists?(Path.join(tmp_dir, ".cursor/commands/controlkeel-review.md"))
  end

  test "sync skips agents already on the current version", %{tmp_dir: tmp_dir} do
    current_version = to_string(Application.spec(:controlkeel, :vsn) || "0.2.0")

    binding = %{
      "workspace_id" => 1,
      "session_id" => 1,
      "agent" => "claude",
      "attached_agents" => %{
        "cursor" => %{
          "target" => "cursor-native",
          "scope" => "project",
          "controlkeel_version" => current_version
        }
      },
      "bootstrap" => %{"mode" => "project", "auto_bootstrapped" => false}
    }

    assert {:ok, written} = Binding.write(binding, tmp_dir)
    assert {:ok, synced, []} = AttachedSync.sync(written, tmp_dir, mode: :project)
    assert synced["attached_agents"]["cursor"]["controlkeel_version"] == current_version
    refute synced["attached_agents"]["cursor"]["synced_at"]
  end
end
