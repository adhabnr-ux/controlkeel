defmodule ControlKeel.Skills.Exporter.WarpOzRuntime do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("warp-oz", project_root, opts))

    readme_path = Path.join(root, "warp-oz/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.warp_oz_runtime_contents(project_root, opts))

    config_path = Path.join(root, "warp-oz/controlkeel-agent-config.json")

    File.write!(
      config_path,
      Jason.encode!(E.warp_oz_agent_config_payload(), pretty: true) <> "\n"
    )

    api_request_path = Path.join(root, "warp-oz/controlkeel-api-request.json")

    File.write!(
      api_request_path,
      Jason.encode!(E.warp_oz_api_request_payload(), pretty: true) <> "\n"
    )

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => api_request_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Warp/Oz runs inherit ControlKeel workflow guidance.",
        "Add this repository to an Oz environment so `.warp/skills/` and `.agents/skills/` become available to cloud agents.",
        "Use `warp-oz/controlkeel-agent-config.json` with `oz agent run-cloud -f ...` for repeatable MCP-enabled runs.",
        "Use `warp-oz/controlkeel-api-request.json` as the starting point for REST/API runs authenticated with `WARP_API_KEY`."
      ]
    )
  end
end
