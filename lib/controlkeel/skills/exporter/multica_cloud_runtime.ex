defmodule ControlKeel.Skills.Exporter.MulticaCloudRuntime do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("multica", project_root, opts))

    readme_path = Path.join(root, "multica-cloud/README.md")
    File.mkdir_p!(Path.dirname(readme_path))

    File.write!(readme_path, """
    # Multica Cloud – ControlKeel Runtime Export

    This directory contains ControlKeel governance assets for Multica Cloud-hosted agent workspaces.

    ## Setup

    1. Place `AGENTS.md` at the repo root so Multica Cloud agents inherit ControlKeel workflow guidance.
    2. Import `controlkeel-mcp.json` into the Multica Cloud agent MCP settings via the Multica web UI.
    3. Configure autopilots (cron-triggered agent tasks) and issue assignments via Multica workspace settings.

    ## MCP Configuration

    Use `controlkeel-mcp.json` as the starting point when wiring the ControlKeel MCP server into a Multica Cloud agent.

    ## Resources

    - Multica docs: https://github.com/multica-ai/multica
    - ControlKeel attach: `controlkeel attach multica` (for local daemon)
    - Cloud export: `controlkeel runtime E.export multica-cloud`
    """)

    config_path = Path.join(root, "multica-cloud/controlkeel-mcp.json")

    File.write!(
      config_path,
      Jason.encode!(
        %{
          "transport" => "STDIO",
          "command" => E.mcp_command(project_root, opts),
          "args" => E.mcp_args(project_root, opts),
          "env" => %{},
          "note" =>
            "Import this into Multica Cloud agent MCP settings via the Multica web UI or CLI (`multica agent mcp add`)."
        },
        pretty: true
      ) <> "\n"
    )

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => config_path, "kind" => "settings"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Multica Cloud agents inherit ControlKeel workflow guidance.",
        "Import `multica-cloud/controlkeel-mcp.json` into Multica Cloud agent MCP settings via the Multica web UI."
      ]
    )
  end
end
