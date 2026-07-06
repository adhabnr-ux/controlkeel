defmodule ControlKeel.CLI.CloudSyncTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.CLI
  alias ControlKeel.Cloud.Workspace.Identity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-cli-sync-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    {:ok, _identity, :created} = Identity.ensure()
    :ok
  end

  describe "cloud sync push" do
    test "returns clear error when endpoint is not configured" do
      result = CLI.run_command(%{command: :cloud_sync_push, options: %{}}, "/tmp")
      assert {:error, message} = result
      assert String.contains?(message, "endpoint not configured")
    end
  end

  describe "cloud sync pull" do
    test "returns clear error when endpoint is not configured" do
      result = CLI.run_command(%{command: :cloud_sync_pull, options: %{}}, "/tmp")
      assert {:error, message} = result
      assert String.contains?(message, "endpoint not configured")
    end
  end

  describe "cloud sync migrate" do
    test "returns migration guidance" do
      result = CLI.run_command(%{command: :cloud_sync_migrate, options: %{}}, "/tmp")
      assert {:ok, lines} = result
      assert is_list(lines)
      assert Enum.any?(lines, &String.contains?(&1, "ecto.migrate"))
    end
  end
end
