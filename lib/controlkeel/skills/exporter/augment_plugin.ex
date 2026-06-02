defmodule ControlKeel.Skills.Exporter.AugmentPlugin do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.augment_agent_contents(skills))

    command_path = Path.join(root, "commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.augment_review_command_contents())

    submit_command_path = Path.join(root, "commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.augment_submit_plan_command_contents())

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Augment", "augment", ".augment/annotate.md")
    )

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Augment"))

    rule_path = Path.join(root, "rules/controlkeel.md")
    File.mkdir_p!(Path.dirname(rule_path))
    File.write!(rule_path, E.augment_rule_contents())

    manifest_path = Path.join(root, ".augment-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(E.augment_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks/hooks.json")
    File.mkdir_p!(Path.dirname(hooks_path))
    File.write!(hooks_path, Jason.encode!(E.augment_hooks_manifest(), pretty: true) <> "\n")

    shell_hook_path = Path.join(root, "hooks/controlkeel-review.sh")
    File.write!(shell_hook_path, E.review_bridge_shell_contents("augment"))
    File.chmod!(shell_hook_path, 0o755)

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    readme_path = Path.join(root, "README.md")
    File.write!(readme_path, E.augment_plugin_readme_contents())

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => rule_path, "kind" => "rules"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => shell_hook_path, "kind" => "hook"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "instructions"}
      ],
      [
        "Run `auggie --plugin-dir #{root}` to test the plugin locally.",
        "The plugin ships hook-native review interception plus the `/controlkeel-review`, `/controlkeel-submit-plan`, `/controlkeel-annotate`, and `/controlkeel-last` commands.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end
end
