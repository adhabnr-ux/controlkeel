defmodule ControlKeel.Skills.Exporter.HermesNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".hermes/skills")
    E.write_skill_tree(skills, skill_root)

    mcp_path = Path.join(root, ".hermes/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("hermes-agent", project_root, opts))

    review_command_path = Path.join(root, ".hermes/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("Hermes", "hermes"))

    submit_command_path = Path.join(root, ".hermes/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("Hermes", "hermes", ".hermes/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".hermes/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Hermes", "hermes", ".hermes/annotate.md")
    )

    last_command_path = Path.join(root, ".hermes/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Hermes"))

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
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `.hermes/skills` into your Hermes config directory or project workspace.",
        "Merge `.hermes/mcp.json` into Hermes MCP configuration and keep `AGENTS.md` in the governed repo."
      ]
    )
  end
end
