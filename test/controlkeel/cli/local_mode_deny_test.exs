defmodule ControlKeel.CLI.LocalModeDenyTest do
  use ExUnit.Case

  alias ControlKeel.CLI

  # Runtime mode lives in global application env. Flip it deterministically and
  # restore the prior value on exit so serial neighbors see the default again.
  defp set_mode!(mode) do
    prior = Application.get_env(:controlkeel, :runtime_mode)
    Application.put_env(:controlkeel, :runtime_mode, mode)

    on_exit(fn ->
      case prior do
        nil -> Application.delete_env(:controlkeel, :runtime_mode)
        value -> Application.put_env(:controlkeel, :runtime_mode, value)
      end
    end)
  end

  describe "org-admin command gating" do
    test "org create, org invite, and org members are denied in local mode" do
      set_mode!(:local)

      for command <- [:org_create, :org_invite, :org_members] do
        assert {:error, message} =
                 CLI.run_command(%{command: command, options: %{}}, System.tmp_dir!())

        assert message =~ "only supported in cloud mode"
        assert message =~ "Please migrate to cloud mode"
      end
    end

    test "the deny message names the command that was rejected" do
      set_mode!(:local)

      assert {:error, create_msg} =
               CLI.run_command(%{command: :org_create, options: %{}}, System.tmp_dir!())

      assert create_msg =~ "org create"

      assert {:error, invite_msg} =
               CLI.run_command(
                 %{command: :org_invite, options: %{}, args: ["x"]},
                 System.tmp_dir!()
               )

      assert invite_msg =~ "org invite"

      assert {:error, members_msg} =
               CLI.run_command(
                 %{command: :org_members, options: %{}, args: ["x"]},
                 System.tmp_dir!()
               )

      assert members_msg =~ "org members"
    end

    test "org commands pass through to their handler outside local mode" do
      set_mode!(:cloud)

      # Reaches the handler, which then complains about the missing option
      # instead of returning the local-mode deny message.
      assert {:error, message} =
               CLI.run_command(%{command: :org_create, options: %{}}, System.tmp_dir!())

      refute message =~ "only supported in cloud mode"
      assert message =~ "Missing required option"
    end
  end
end
