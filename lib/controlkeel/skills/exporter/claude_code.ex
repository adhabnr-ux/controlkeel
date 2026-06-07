defmodule ControlKeel.Skills.Exporter.ClaudeCode do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.claude_plugin_agent_contents(skills))

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Claude Code", "claude-code"))

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Claude Code", "claude-code", ".claude/annotate.md")
    )

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Claude Code"))

    manifest_path = Path.join(root, ".claude-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(E.claude_plugin_manifest(), pretty: true) <> "\n")

    marketplace_path = Path.join(root, ".claude-plugin/marketplace.json")

    File.write!(
      marketplace_path,
      Jason.encode!(E.claude_marketplace_manifest(), pretty: true) <> "\n"
    )

    hooks_path = Path.join(root, "hooks/hooks.json")
    File.mkdir_p!(Path.dirname(hooks_path))

    File.write!(
      hooks_path,
      Jason.encode!(E.claude_hooks_manifest(), pretty: true) <> "\n"
    )

    shell_hook_path = Path.join(root, "hooks/controlkeel-review.sh")
    File.write!(shell_hook_path, E.review_bridge_shell_contents("claude-code"))
    File.chmod!(shell_hook_path, 0o755)

    powershell_hook_path = Path.join(root, "hooks/controlkeel-review.ps1")
    File.write!(powershell_hook_path, E.review_bridge_powershell_contents("claude-code"))

    lifecycle_hook_paths =
      Enum.map(E.claude_plugin_hook_scripts(), fn {name, content_fn} ->
        path = Path.join(root, "hooks/#{name}")
        File.write!(path, content_fn.())
        File.chmod!(path, 0o755)
        %{"path" => path, "kind" => "hook"}
      end)

    manual_hook_path = Path.join(root, "hooks/manual-settings.json")
    File.write!(manual_hook_path, Jason.encode!(E.claude_manual_settings(), pretty: true) <> "\n")

    settings_path = Path.join(root, "settings.json")

    File.write!(
      settings_path,
      Jason.encode!(%{"agent" => "controlkeel-operator"}, pretty: true) <> "\n"
    )

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => marketplace_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => shell_hook_path, "kind" => "hook"},
        %{"path" => powershell_hook_path, "kind" => "hook"}
        | lifecycle_hook_paths
      ] ++
        [
          %{"path" => manual_hook_path, "kind" => "settings"},
          %{"path" => mcp_path, "kind" => "mcp"},
          %{"path" => settings_path, "kind" => "settings"}
        ],
      [
        "Run `claude --plugin-dir #{root}` to test the plugin locally.",
        "Add as a marketplace: `claude plugin marketplace add #{root}`",
        "The plugin also ships `/controlkeel-review`, `/controlkeel-annotate`, and `/controlkeel-last` command prompts for explicit governed review passes.",
        "Use hooks/manual-settings.json when you prefer Claude's manual hook installation path.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template.",
        "Load in Agent SDK: `plugins: [{ type: \"local\", path: \"#{root}\" }]` with `allowedTools: [\"Skill\", \"mcp__controlkeel__*\"]` — skills, hooks, and the operator agent are loaded from the bundle automatically."
      ]
    )
  end
end
