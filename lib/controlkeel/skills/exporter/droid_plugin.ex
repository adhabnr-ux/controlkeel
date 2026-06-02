defmodule ControlKeel.Skills.Exporter.DroidPlugin do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    droid_path = Path.join(root, "droids/controlkeel.md")
    File.mkdir_p!(Path.dirname(droid_path))
    File.write!(droid_path, E.droid_profile_contents())

    review_command_path = Path.join(root, "commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(review_command_path))
    File.write!(review_command_path, E.droid_review_command_contents())

    submit_command_path = Path.join(root, "commands/controlkeel-submit-plan.md")
    File.write!(submit_command_path, E.droid_submit_plan_command_contents())

    annotate_command_path = Path.join(root, "commands/controlkeel-annotate.md")
    File.write!(annotate_command_path, E.droid_annotate_command_contents())

    last_command_path = Path.join(root, "commands/controlkeel-last.md")
    File.write!(last_command_path, E.droid_last_command_contents())

    manifest_path = Path.join(root, ".factory-plugin/plugin.json")
    File.mkdir_p!(Path.dirname(manifest_path))
    File.write!(manifest_path, Jason.encode!(E.droid_plugin_manifest(), pretty: true) <> "\n")

    hooks_path = Path.join(root, "hooks/hooks.json")
    File.mkdir_p!(Path.dirname(hooks_path))
    File.write!(hooks_path, Jason.encode!(E.empty_hooks_manifest(), pretty: true) <> "\n")

    mcp_path = Path.join(root, "mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    readme_path = Path.join(root, "README.md")
    File.write!(readme_path, E.droid_plugin_readme_contents())

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => droid_path, "kind" => "agent"},
        %{"path" => review_command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => hooks_path, "kind" => "hooks"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => readme_path, "kind" => "instructions"}
      ],
      [
        "Use `controlkeel plugin E.export droid` to produce this shareable Factory plugin bundle.",
        "Install it through Droid's plugin marketplace flow, for example by adding the exported directory as a local marketplace and then installing `controlkeel@droid-plugin`."
      ]
    )
  end
end
