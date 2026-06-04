defmodule ControlKeel.CLI.DetachTest do
  use ControlKeel.DataCase

  import ExUnit.CaptureIO

  alias ControlKeel.CLI
  alias ControlKeel.CodexConfig
  alias ControlKeel.LocalProject
  alias ControlKeel.ProjectBinding

  setup do
    tmp = Path.join(System.tmp_dir!(), "ck-detach-#{System.unique_integer([:positive])}")
    File.rm_rf!(tmp)
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, binding, _session, _state} = LocalProject.load_or_bootstrap(tmp)
    {:ok, tmp: tmp, binding: binding}
  end

  defp run_detach(tmp, agent) do
    capture_io(fn ->
      assert 0 ==
               CLI.execute(
                 %{command: :detach, args: [agent], options: %{project_root: tmp}},
                 project_root: tmp
               )
    end)
  end

  # Keep a second agent attached so the binding survives detach for assertions.
  defp attach_two(binding, tmp, agents) do
    updated =
      Enum.reduce(agents, binding, fn {key, attrs}, acc ->
        ProjectBinding.update_attached_agent(acc, key, attrs)
      end)

    {:ok, _} = ProjectBinding.write_effective(updated, tmp, mode: :project)
    :ok
  end

  test "detach removes only the controlkeel MCP entry, keeping other servers", %{
    tmp: tmp,
    binding: binding
  } do
    cursor = Path.join(tmp, ".cursor/mcp.json")
    File.mkdir_p!(Path.dirname(cursor))

    File.write!(
      cursor,
      Jason.encode!(%{
        "mcpServers" => %{
          "controlkeel" => %{"command" => "controlkeel"},
          "other" => %{"command" => "x"}
        }
      })
    )

    attach_two(binding, tmp, [
      {"cursor",
       %{
         "server_name" => "controlkeel",
         "ide" => "cursor",
         "config_path" => cursor,
         "scope" => "project"
       }},
      {"opencode", %{"server_name" => "controlkeel", "scope" => "user"}}
    ])

    run_detach(tmp, "cursor")

    config = Jason.decode!(File.read!(cursor))
    refute Map.has_key?(config["mcpServers"], "controlkeel")
    assert Map.has_key?(config["mcpServers"], "other")

    {:ok, reloaded, _mode} = ProjectBinding.read_effective(tmp)
    refute Map.has_key?(reloaded["attached_agents"] || %{}, "cursor")
    assert Map.has_key?(reloaded["attached_agents"] || %{}, "opencode")
  end

  test "detach resolves the stored key when attach used a dash/underscore variant", %{
    tmp: tmp,
    binding: binding
  } do
    # attach stores claude-code under "claude_code"; detaching "claude-code" must resolve it.
    attach_two(binding, tmp, [
      {"claude_code", %{"server_name" => "controlkeel", "scope" => "local"}},
      {"opencode", %{"server_name" => "controlkeel", "scope" => "user"}}
    ])

    # claude binary absent -> MCP removal degrades to a no-op, detach still succeeds.
    System.put_env("CONTROLKEEL_CLAUDE_BIN", "ck-no-such-claude-binary")
    on_exit(fn -> System.delete_env("CONTROLKEEL_CLAUDE_BIN") end)

    run_detach(tmp, "claude-code")

    {:ok, reloaded, _mode} = ProjectBinding.read_effective(tmp)
    refute Map.has_key?(reloaded["attached_agents"] || %{}, "claude_code")
    assert Map.has_key?(reloaded["attached_agents"] || %{}, "opencode")
  end

  test "detaching an agent that was never attached reports a clear error", %{tmp: tmp} do
    output =
      capture_io(:stderr, fn ->
        refute 0 ==
                 CLI.execute(
                   %{command: :detach, args: ["cursor"], options: %{project_root: tmp}},
                   project_root: tmp
                 )
      end)

    assert output =~ "not attached"
  end

  test "CodexConfig.remove strips the managed block but preserves user content", %{tmp: tmp} do
    path = Path.join(tmp, "config.toml")
    {:ok, _} = CodexConfig.write(path, %{command: "controlkeel", args: ["mcp"]})
    File.write!(path, "model = \"gpt-x\"\n" <> File.read!(path))

    assert File.read!(path) =~ "mcp_servers.controlkeel"

    assert :ok = CodexConfig.remove(path)
    remaining = File.read!(path)
    refute remaining =~ "mcp_servers.controlkeel"
    refute remaining =~ "controlkeel:start"
    assert remaining =~ "model = \"gpt-x\""
  end
end
