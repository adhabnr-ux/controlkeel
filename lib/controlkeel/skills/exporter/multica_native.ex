defmodule ControlKeel.Skills.Exporter.MulticaNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    compat_skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, compat_skill_root)

    config_path = Path.join(root, ".multica/controlkeel-mcp.json")
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n"
    )

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("multica", project_root, opts))

    review_command_path = Path.join(root, ".multica/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Multica", "multica"))

    submit_command_path = Path.join(root, ".multica/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Multica", "multica", ".multica/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".multica/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Multica", "multica", ".multica/annotate.md")
    )

    last_command_path = Path.join(root, ".multica/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Multica"))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => compat_skill_root, "kind" => "skills"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => config_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Keep `.agents/skills/` in the repo so Multica-orchestrated coding agents can discover governed skills.",
        "Import `.multica/controlkeel-mcp.json` into the Multica agent MCP settings via the Multica web UI or CLI.",
        "Ensure the Multica daemon is running (`multica daemon start`) before attaching ControlKeel."
      ]
    )
  end
end
