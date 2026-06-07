defmodule ControlKeel.Skills.Exporter.OpenclawNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    config_path = Path.join(root, ".openclaw/openclaw.json")
    File.mkdir_p!(Path.dirname(config_path))

    File.write!(
      config_path,
      Jason.encode!(E.openclaw_config_snippet(project_root, opts), pretty: true) <> "\n"
    )

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("openclaw", project_root, opts))

    review_command_path = Path.join(root, ".openclaw/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.host_review_command_contents("OpenClaw", "openclaw"))

    submit_command_path = Path.join(root, ".openclaw/commands/controlkeel-submit-plan.md")

    File.write!(
      submit_command_path,
      E.host_submit_plan_command_contents("OpenClaw", "openclaw", ".openclaw/review-plan.md")
    )

    annotate_command_path = Path.join(root, ".openclaw/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("OpenClaw", "openclaw", ".openclaw/annotate.md")
    )

    last_command_path = Path.join(root, ".openclaw/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("OpenClaw"))

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
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Copy `skills/` into your OpenClaw workspace or managed skills directory.",
        "Merge `.openclaw/openclaw.json` into OpenClaw settings to register the ControlKeel MCP server and skill path."
      ]
    )
  end
end
