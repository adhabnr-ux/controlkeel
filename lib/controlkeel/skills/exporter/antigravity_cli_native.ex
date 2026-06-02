defmodule ControlKeel.Skills.Exporter.AntigravityCliNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    # 1. Plugin bundle — the richest surface Antigravity supports
    plugin_root = Path.join(root, ".agents/plugins/controlkeel")
    File.mkdir_p!(plugin_root)

    # Plugin manifest
    plugin_manifest = Path.join(plugin_root, "plugin.json")
    File.write!(plugin_manifest, Jason.encode!(%{"name" => "controlkeel"}, pretty: true) <> "\n")

    # Plugin skills (inside plugin bundle)
    plugin_skill_root = Path.join(plugin_root, "skills")
    E.write_skill_tree(skills, plugin_skill_root)

    # Plugin agents
    agent_path = Path.join(plugin_root, "agents/controlkeel-operator.md")
    File.mkdir_p!(Path.dirname(agent_path))
    File.write!(agent_path, E.antigravity_agent_contents())

    # Plugin rules
    rules_dir = Path.join(plugin_root, "rules")
    File.mkdir_p!(rules_dir)
    File.write!(Path.join(rules_dir, "controlkeel.md"), E.antigravity_rules_contents())

    # Plugin hooks — governance gate
    plugin_hooks_path = Path.join(plugin_root, "hooks.json")

    File.write!(
      plugin_hooks_path,
      Jason.encode!(E.antigravity_hooks_manifest(project_root, opts), pretty: true) <> "\n"
    )

    # Plugin MCP config
    plugin_mcp_path = Path.join(plugin_root, "mcp_config.json")

    File.write!(
      plugin_mcp_path,
      Jason.encode!(E.antigravity_mcp_config(project_root, opts), pretty: true) <> "\n"
    )

    # 2. Workspace-level skills (for agents that discover .agents/skills/)
    ws_skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, ws_skill_root)

    # 3. Workspace-level rules
    ws_rules_dir = Path.join(root, ".agents/rules")
    File.mkdir_p!(ws_rules_dir)
    File.write!(Path.join(ws_rules_dir, "controlkeel.md"), E.antigravity_rules_contents())

    # 4. Workspace-level hooks
    ws_hooks_path = Path.join(root, ".agents/hooks.json")

    File.write!(
      ws_hooks_path,
      Jason.encode!(E.antigravity_hooks_manifest(project_root, opts), pretty: true) <> "\n"
    )

    # 5. Workspace-level MCP config
    ws_mcp_path = Path.join(root, ".agents/mcp_config.json")

    File.write!(
      ws_mcp_path,
      Jason.encode!(E.antigravity_mcp_config(project_root, opts), pretty: true) <> "\n"
    )

    # 6. Context files
    gemini_md = Path.join(root, "GEMINI.md")
    File.write!(gemini_md, E.instructions_only_contents("antigravity-cli", project_root, opts))

    agents_md = Path.join(root, "AGENTS.md")
    File.write!(agents_md, E.instructions_only_contents("antigravity-cli", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => plugin_root, "kind" => "plugin"},
        %{"path" => plugin_manifest, "kind" => "settings"},
        %{"path" => plugin_skill_root, "kind" => "skills"},
        %{"path" => agent_path, "kind" => "agent"},
        %{"path" => Path.join(rules_dir, "controlkeel.md"), "kind" => "rules"},
        %{"path" => plugin_hooks_path, "kind" => "hooks"},
        %{"path" => plugin_mcp_path, "kind" => "mcp"},
        %{"path" => ws_skill_root, "kind" => "skills"},
        %{"path" => Path.join(ws_rules_dir, "controlkeel.md"), "kind" => "rules"},
        %{"path" => ws_hooks_path, "kind" => "hooks"},
        %{"path" => ws_mcp_path, "kind" => "mcp"},
        %{"path" => gemini_md, "kind" => "instructions"},
        %{"path" => agents_md, "kind" => "instructions"}
      ],
      [
        "The plugin bundle at `.agents/plugins/controlkeel/` contains skills, agents, rules, hooks, and MCP config as a single installable unit.",
        "Antigravity CLI discovers workspace plugins automatically from `.agents/plugins/`.",
        "To install globally, copy the plugin to `~/.gemini/config/plugins/controlkeel/`.",
        "Workspace skills, rules, hooks, and MCP config in `.agents/` are also auto-discovered.",
        "Run `agy plugin list` to verify the controlkeel plugin is loaded."
      ]
    )
  end
end
