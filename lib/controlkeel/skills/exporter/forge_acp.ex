defmodule ControlKeel.Skills.Exporter.ForgeAcp do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    acp_path = Path.join(root, ".forge/controlkeel.acp.json")
    File.mkdir_p!(Path.dirname(acp_path))

    File.write!(
      acp_path,
      Jason.encode!(E.forge_acp_manifest(project_root, opts), pretty: true) <> "\n"
    )

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("forge", project_root, opts))

    review_command_path = Path.join(root, ".forge/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Forge", "forge"))

    submit_command_path = Path.join(root, ".forge/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Forge", "forge", ".forge/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".forge/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Forge", "forge", ".forge/annotate.md")
    )

    last_command_path = Path.join(root, ".forge/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Forge"))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => acp_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Use `.forge/controlkeel.acp.json` when Forge can open an ACP session; keep `.mcp.json` as the portable fallback."
      ]
    )
  end
end
