defmodule ControlKeel.Skills.Exporter.GeminiCliNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    # 1. Extension manifest
    manifest_path = Path.join(root, "gemini-extension.json")

    File.write!(
      manifest_path,
      Jason.encode!(E.gemini_extension_manifest(project_root, opts), pretty: true) <> "\n"
    )

    # 2. Custom command — /controlkeel:review
    command_path = Path.join(root, ".gemini/commands/controlkeel/review.toml")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.gemini_command_contents())

    submit_plan_command_path = Path.join(root, ".gemini/commands/controlkeel/submit-plan.toml")
    File.write!(submit_plan_command_path, E.gemini_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".gemini/commands/controlkeel/annotate.toml")
    File.write!(annotate_command_path, E.gemini_annotate_command_contents())

    last_command_path = Path.join(root, ".gemini/commands/controlkeel/last.toml")
    File.write!(last_command_path, E.gemini_last_command_contents())

    # 3. Agent skill
    skill_path = Path.join(root, "skills/controlkeel-governance/SKILL.md")
    File.mkdir_p!(Path.dirname(skill_path))
    File.write!(skill_path, E.gemini_skill_contents())

    # 4. MCP config
    mcp_path = Path.join(root, ".gemini/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    # 5. GEMINI.md context
    gemini_md_path = Path.join(root, "GEMINI.md")
    File.write!(gemini_md_path, E.instructions_only_contents("gemini-cli", project_root, opts))

    extension_readme_path = Path.join(root, "README.md")
    File.write!(extension_readme_path, E.gemini_extension_readme_contents())

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "settings"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_plan_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => skill_path, "kind" => "skills"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => gemini_md_path, "kind" => "instructions"},
        %{"path" => extension_readme_path, "kind" => "instructions"}
      ],
      [
        "Install with `gemini extensions link .` or copy the directory into `~/.gemini/extensions/controlkeel/`.",
        "The `/controlkeel:review`, `/controlkeel:submit-plan`, `/controlkeel:annotate`, and `/controlkeel:last` commands plus the `controlkeel-governance` skill are auto-discovered."
      ]
    )
  end
end
