defmodule ControlKeel.CLI.SelfhostTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.CLI

  @env_vars ~w(DATABASE_URL SECRET_KEY_BASE PHX_HOST)

  setup do
    previous = Map.new(@env_vars, fn name -> {name, System.get_env(name)} end)
    Enum.each(@env_vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  describe "selfhost verify" do
    test "errors when required env vars are missing" do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :selfhost_verify, options: %{}, args: []},
                 File.cwd!()
               )

      assert msg =~ "Ready: false"
      assert msg =~ "[MISS] DATABASE_URL"
      assert msg =~ "[MISS] SECRET_KEY_BASE"
      assert msg =~ "[MISS] PHX_HOST"
    end

    test "returns ok when all required env vars are present in local mode" do
      Enum.each(@env_vars, &System.put_env(&1, "x"))

      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :selfhost_verify, options: %{}, args: []},
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Ready: true"))
      refute Enum.any?(lines, &(&1 =~ "[MISS]"))
    end
  end

  describe "selfhost manifest" do
    test "lists the release + migrations + INSTALL.md" do
      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :selfhost_manifest, options: %{}, args: []},
                 File.cwd!()
               )

      joined = Enum.join(lines, "\n")
      assert joined =~ "_build/prod/rel/controlkeel/"
      assert joined =~ "priv/repo/migrations/"
      assert joined =~ "INSTALL.md"
    end
  end

  describe "selfhost install-guide" do
    test "prints the INSTALL.md markdown" do
      assert {:ok, [body]} =
               CLI.run_command(
                 %{command: :selfhost_install_guide, options: %{}, args: []},
                 File.cwd!()
               )

      assert body =~ "# ControlKeel self-host install"
      assert body =~ "DATABASE_URL"
      assert body =~ "controlkeel selfhost verify"
    end
  end

  describe "CLI.parse/1" do
    test "parses selfhost verify" do
      assert {:ok, parsed} = CLI.parse(["selfhost", "verify"])
      assert parsed.command == :selfhost_verify
    end

    test "parses selfhost manifest" do
      assert {:ok, parsed} = CLI.parse(["selfhost", "manifest"])
      assert parsed.command == :selfhost_manifest
    end

    test "parses selfhost install-guide" do
      assert {:ok, parsed} = CLI.parse(["selfhost", "install-guide"])
      assert parsed.command == :selfhost_install_guide
    end
  end
end
