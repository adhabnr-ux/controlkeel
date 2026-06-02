defmodule ControlKeel.Skills.Exporter.CodexPlugin do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.copilot_agent_contents(skills))

    diff_command_path = Path.join(root, "commands/controlkeel-diff-review.md")
    File.mkdir_p!(Path.dirname(diff_command_path))
    File.write!(diff_command_path, E.codex_diff_review_command_contents())

    completion_command_path = Path.join(root, "commands/controlkeel-completion-review.md")
    File.mkdir_p!(Path.dirname(completion_command_path))
    File.write!(completion_command_path, E.codex_completion_review_command_contents())

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.write!(review_command_path, E.codex_review_command_contents())

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, E.codex_annotate_command_contents())

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, E.codex_last_command_contents())

    manifest_path = Path.join(root, ".codex-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(E.codex_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks.json")
    File.write!(hooks_path, Jason.encode!(E.empty_hooks_manifest(), pretty: true) <> "\n")

    app_path = Path.join(root, ".app.json")
    File.write!(app_path, Jason.encode!(E.codex_app_manifest(), pretty: true) <> "\n")

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    marketplace_path = Path.join(root, ".agents/plugins/marketplace.json")
    File.mkdir_p!(Path.dirname(marketplace_path))

    File.write!(
      marketplace_path,
      Jason.encode!(E.codex_marketplace_manifest(), pretty: true) <> "\n"
    )

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => diff_command_path, "kind" => "command"},
        %{"path" => completion_command_path, "kind" => "command"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => app_path, "kind" => "app"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => marketplace_path, "kind" => "marketplace"}
      ],
      [
        "Install this bundle as a Codex plugin or add it to your repo-local Codex marketplace.",
        "Use .mcp.json for local stdio MCP and .mcp.hosted.json as the hosted MCP template."
      ]
    )
  end
end
