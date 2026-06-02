defmodule ControlKeel.Skills.Exporter.Windsurf do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    rule_path = Path.join(root, ".windsurf/rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, E.windsurf_rule_contents())

    command_path = Path.join(root, ".windsurf/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.windsurf_command_contents())

    submit_command_path = Path.join(root, ".windsurf/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Windsurf", "windsurf", ".windsurf/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".windsurf/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Windsurf", "windsurf", ".windsurf/annotate.md")
    )

    last_command_path = Path.join(root, ".windsurf/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Windsurf"))

    workflow_path = Path.join(root, ".windsurf/workflows/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(workflow_path))
    File.write!(workflow_path, E.windsurf_workflow_contents())

    workspace_hooks_path = Path.join(root, ".windsurf/hooks.json")

    File.write!(
      workspace_hooks_path,
      Jason.encode!(E.windsurf_workspace_hook_manifest(), pretty: true) <> "\n"
    )

    hook_path = Path.join(root, ".windsurf/hooks/controlkeel-review.json")
    File.mkdir_p!(Path.dirname(hook_path))
    File.write!(hook_path, Jason.encode!(E.windsurf_hook_manifest(), pretty: true) <> "\n")

    hook_script_path = Path.join(root, ".windsurf/hooks/controlkeel-review.sh")
    File.write!(hook_script_path, E.review_bridge_shell_contents("windsurf"))
    File.chmod!(hook_script_path, 0o755)

    mcp_path = Path.join(root, ".windsurf/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("windsurf", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => workflow_path, "kind" => "workflow"},
        %{"path" => workspace_hooks_path, "kind" => "hooks"},
        %{"path" => hook_path, "kind" => "hook"},
        %{"path" => hook_script_path, "kind" => "hook"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.windsurf/rules`, `.windsurf/workflows`, and `.windsurf/hooks` in the repo so Windsurf loads ControlKeel guidance, Cascade workflows, and hook-native review interception.",
        "Use `.windsurf/hooks.json` as the canonical workspace hook config; the per-hook JSON and shell script are included as portable review assets.",
        "Use .windsurf/mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end
end
