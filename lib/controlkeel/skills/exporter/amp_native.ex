defmodule ControlKeel.Skills.Exporter.AmpNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    # 1. TypeScript plugin
    plugin_path = Path.join(root, ".amp/plugins/controlkeel-governance.ts")
    File.mkdir_p!(Path.dirname(plugin_path))
    File.write!(plugin_path, E.amp_plugin_contents())

    skill_path = Path.join(root, ".agents/skills/controlkeel-governance/SKILL.md")
    File.mkdir_p!(Path.dirname(skill_path))
    File.write!(skill_path, E.amp_skill_contents())

    skill_mcp_path = Path.join(root, ".agents/skills/controlkeel-governance/mcp.json")

    File.write!(
      skill_mcp_path,
      Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    command_path = Path.join(root, ".amp/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.amp_command_contents())

    submit_command_path = Path.join(root, ".amp/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Amp", "amp", ".amp/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".amp/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Amp", "amp", ".amp/annotate.md")
    )

    last_command_path = Path.join(root, ".amp/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Amp"))

    package_json_path = Path.join(root, ".amp/package.json")
    File.write!(package_json_path, Jason.encode!(E.amp_package_manifest(), pretty: true) <> "\n")

    # 2. MCP config
    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    # 3. Instructions
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("amp", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => plugin_path, "kind" => "plugin"},
        %{"path" => skill_path, "kind" => "skills"},
        %{"path" => skill_mcp_path, "kind" => "mcp"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => package_json_path, "kind" => "package"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.amp/plugins/` and `.amp/commands/` into your project root for Amp Neo Plugin API governance.",
        "Install or sync the bundled `.agents/skills/controlkeel-governance` with your preferred Agent Skills package manager when skills are enabled.",
        "Merge `.mcp.json` into your project's MCP config; CK policy gates remain required even if Amp runs without default prompts."
      ]
    )
  end
end
