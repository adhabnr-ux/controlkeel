defmodule ControlKeel.Skills.Exporter.OpenclawPlugin do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, skills, opts) do
    skill_root = Path.join(root, "skills")
    E.write_skill_tree(skills, skill_root)

    manifest_path = Path.join(root, "openclaw.plugin.json")
    File.write!(manifest_path, Jason.encode!(E.openclaw_plugin_manifest(), pretty: true) <> "\n")

    package_json = Path.join(root, "package.json")

    File.write!(
      package_json,
      Jason.encode!(
        %{"name" => "controlkeel-openclaw", "private" => true, "version" => E.app_version()},
        pretty: true
      ) <> "\n"
    )

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("openclaw", project_root, opts))

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => manifest_path, "kind" => "manifest"},
        %{"path" => package_json, "kind" => "package"},
        %{"path" => skill_root, "kind" => "skills"},
        %{"path" => mcp_path, "kind" => "mcp"},
        %{"path" => agents_path, "kind" => "instructions"}
      ],
      [
        "Install this folder with `openclaw plugins install <path>` or unpack it into a local plugin workspace.",
        "Use `AGENTS.md` in the governed repo for shared ControlKeel context."
      ]
    )
  end
end
