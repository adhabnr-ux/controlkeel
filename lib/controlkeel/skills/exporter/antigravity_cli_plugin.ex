defmodule ControlKeel.Skills.Exporter.AntigravityCliPlugin do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    # Portable plugin bundle for global install or marketplace distribution
    plugin_root = Path.join(root, "controlkeel")
    File.mkdir_p!(plugin_root)

    plugin_manifest = Path.join(plugin_root, "plugin.json")
    File.write!(plugin_manifest, Jason.encode!(%{"name" => "controlkeel"}, pretty: true) <> "\n")

    skill_root = Path.join(plugin_root, "skills")
    E.write_skill_tree(skills, skill_root)

    agent_path = Path.join(plugin_root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.antigravity_agent_contents())

    rules_dir = Path.join(plugin_root, "rules")
    File.mkdir_p!(rules_dir)
    File.write!(Path.join(rules_dir, "controlkeel.md"), E.antigravity_rules_contents())

    hooks_path = Path.join(plugin_root, "hooks.json")

    File.write!(
      hooks_path,
      Jason.encode!(E.antigravity_hooks_manifest(project_root, opts), pretty: true) <> "\n"
    )

    mcp_path = Path.join(plugin_root, "mcp_config.json")

    File.write!(
      mcp_path,
      Jason.encode!(E.antigravity_mcp_config(project_root, opts), pretty: true) <> "\n"
    )

    readme_path = Path.join(root, "README.md")
    File.write!(readme_path, E.antigravity_plugin_readme_contents())

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => plugin_manifest, "kind" => "settings"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => Path.join(rules_dir, "controlkeel.md"), "kind" => "rules"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "instructions"}
      ],
      [
        "Install globally: copy the `controlkeel/` directory to `~/.gemini/config/plugins/controlkeel/`.",
        "Or install per-workspace: copy to `.agents/plugins/controlkeel/`.",
        "Run `agy plugin list` to verify."
      ]
    )
  end
end
