defmodule ControlKeel.Skills.Exporter.ClaudeStandalone do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".claude/skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, ".claude/agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.claude_agent_contents(skills))

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    claude_md = Path.join(root, "CLAUDE.md")
    File.write!(claude_md, E.instructions_only_contents("claude", project_root, opts))

    settings_path = Path.join(root, ".claude/settings.json")
    File.write!(settings_path, Jason.encode!(E.claude_manual_settings(), pretty: true) <> "\n")

    review_command_path = Path.join(root, ".claude/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Claude Code", "claude-code"))

    submit_command_path = Path.join(root, ".claude/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Claude Code", "claude-code", ".claude/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".claude/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Claude Code", "claude-code", ".claude/annotate.md")
    )

    last_command_path = Path.join(root, ".claude/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Claude Code"))

    hook_assets = ControlKeel.Skills.ClaudeHooks.write_hooks(root)

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => claude_md, "kind" => "instructions"},
        %{"path" => settings_path, "kind" => "settings"}
      ] ++ hook_assets,
      [
        "Copy .claude/skills, .claude/agents into your project or home .claude directory.",
        "Merge .claude/settings.json hooks into your existing settings.json (or copy if absent).",
        "Merge the generated .mcp.json into Claude's MCP configuration if needed.",
        "Use in Agent SDK: set `settingSources: [\"user\", \"project\"]` and `allowedTools: [\"Skill\", \"mcp__controlkeel__*\"]` so the SDK discovers CK skills, agents, and hooks from the filesystem.",
        "Caution: `settingSources: []` in multi-tenant SDK deployments bypasses CK governance entirely."
      ]
    )
  end
end
