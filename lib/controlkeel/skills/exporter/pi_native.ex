defmodule ControlKeel.Skills.Exporter.PiNative do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, ".agents/skills")
    E.write_skill_tree(skills, skill_root)

    command_path = Path.join(root, ".pi/commands/controlkeel-review.md")
    File.mkdir_p!(Path.dirname(command_path))
    File.write!(command_path, E.pi_command_contents())

    submit_command_path = Path.join(root, ".pi/commands/controlkeel-submit-plan.md")
    File.mkdir_p!(Path.dirname(submit_command_path))
    File.write!(submit_command_path, E.pi_submit_plan_command_contents())

    annotate_command_path = Path.join(root, ".pi/commands/controlkeel-annotate.md")

    File.write!(
      annotate_command_path,
      E.host_annotate_command_contents("Pi", "pi", ".pi/annotate.md")
    )

    last_command_path = Path.join(root, ".pi/commands/controlkeel-last.md")
    File.write!(last_command_path, E.host_last_command_contents("Pi"))

    phase_config_path = Path.join(root, ".pi/controlkeel.json")
    File.mkdir_p!(Path.dirname(phase_config_path))

    File.write!(
      phase_config_path,
      Jason.encode!(E.pi_phase_manifest(project_root, opts), pretty: true) <> "\n"
    )

    mcp_path = Path.join(root, ".pi/mcp.json")
    File.mkdir_p!(Path.dirname(mcp_path))
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    extension_path = Path.join(root, "pi-extension.json")

    File.write!(
      extension_path,
      Jason.encode!(E.pi_extension_manifest(project_root, opts), pretty: true) <> "\n"
    )

    package_json_path = Path.join(root, "package.json")
    File.write!(package_json_path, Jason.encode!(E.pi_package_manifest(), pretty: true) <> "\n")

    package_readme_path = Path.join(root, "README.md")
    File.write!(package_readme_path, E.pi_package_readme_contents())

    instructions_path = Path.join(root, "PI.md")
    File.write!(instructions_path, E.instructions_only_contents("pi", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => command_path, "kind" => "command"},
        %{"path" => submit_command_path, "kind" => "command"},
        %{"path" => annotate_command_path, "kind" => "command"},
        %{"path" => last_command_path, "kind" => "command"},
        %{"path" => phase_config_path, "kind" => "settings"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => extension_path, "kind" => "plugin"},
        %{"path" => package_json_path, "kind" => "package"},
        %{"path" => package_readme_path, "kind" => "instructions"},
        %{"path" => instructions_path, "kind" => "instructions"}
      ],
      [
        "Keep `.pi/controlkeel.json` and `.pi/commands/` in the repo so Pi can switch between planning and execution with a governed plan file.",
        "Use `.pi/mcp.json` for local stdio MCP and `.mcp.hosted.json` as the hosted MCP template.",
        "Install `pi-extension.json` into Pi's local extension directory when a standalone extension link flow is preferred.",
        "For direct npm installs on Pi builds that support extension packages, use `pi install npm:@aryaminus/controlkeel-pi-extension`."
      ]
    )
  end
end
