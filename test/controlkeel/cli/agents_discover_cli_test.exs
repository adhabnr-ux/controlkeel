defmodule ControlKeel.CLI.AgentsDiscoverTest do
  use ExUnit.Case, async: false

  alias ControlKeel.CLI

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "ck-cli-inv-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    File.mkdir_p!(Path.join(tmp, ".cursor"))
    File.write!(Path.join(tmp, "AGENTS.md"), "x")

    {:ok, tmp: tmp}
  end

  describe "agents discover" do
    test "prints summary and rows for a populated directory", %{tmp: tmp} do
      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :agents_discover, options: %{}, args: [tmp]},
                 File.cwd!()
               )

      joined = Enum.join(lines, "\n")
      assert joined =~ "Agent inventory scan"
      assert joined =~ "Total hits:"
      assert joined =~ "cursor"
      assert joined =~ "agents-md"
    end

    test "emits JSON when --json is set", %{tmp: tmp} do
      assert {:ok, [body]} =
               CLI.run_command(
                 %{command: :agents_discover, options: %{json: true}, args: [tmp]},
                 File.cwd!()
               )

      decoded = Jason.decode!(body)
      assert is_list(decoded["hits"])
      assert is_map(decoded["summary"])
      assert decoded["summary"]["total"] >= 2
    end

    test "errors on missing path", %{} do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :agents_discover, options: %{}, args: ["/nope/missing-#{System.unique_integer([:positive])}"]},
                 File.cwd!()
               )

      assert msg =~ "Path not found"
    end

    test "errors when path is a regular file" do
      file = Path.join(System.tmp_dir!(), "ck-inv-file-#{System.unique_integer([:positive])}.txt")
      File.write!(file, "x")
      on_exit(fn -> File.rm!(file) end)

      assert {:error, msg} =
               CLI.run_command(
                 %{command: :agents_discover, options: %{}, args: [file]},
                 File.cwd!()
               )

      assert msg =~ "Not a directory"
    end

    test "honors --max-depth option", %{tmp: tmp} do
      deep = Path.join([tmp, "a", "b", "c", "d", "e"])
      File.mkdir_p!(Path.join(deep, ".opencode"))

      {:ok, [body_shallow]} =
        CLI.run_command(
          %{command: :agents_discover, options: %{json: true, max_depth: 2}, args: [tmp]},
          File.cwd!()
        )

      {:ok, [body_deep]} =
        CLI.run_command(
          %{command: :agents_discover, options: %{json: true, max_depth: 10}, args: [tmp]},
          File.cwd!()
        )

      shallow_hosts =
        Jason.decode!(body_shallow)["hits"]
        |> Enum.map(& &1["host"])

      deep_hosts =
        Jason.decode!(body_deep)["hits"]
        |> Enum.map(& &1["host"])

      refute "opencode" in shallow_hosts
      assert "opencode" in deep_hosts
    end
  end

  describe "CLI.parse/1" do
    test "parses agents discover with path argument" do
      assert {:ok, parsed} = CLI.parse(["agents", "discover", "."])
      assert parsed.command == :agents_discover
      assert parsed.args == ["."]
    end
  end
end
