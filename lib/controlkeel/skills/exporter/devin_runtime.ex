defmodule ControlKeel.Skills.Exporter.DevinRuntime do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("devin", project_root, opts))

    readme_path = Path.join(root, "devin/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.devin_runtime_contents(project_root, opts))

    config_path = Path.join(root, "devin/controlkeel-mcp.json")

    File.write!(
      config_path,
      Jason.encode!(
        %{
          "transport" => "STDIO",
          "command" => E.mcp_command(project_root, opts),
          "args" => E.mcp_args(project_root, opts),
          "env_variables" => %{},
          "note" =>
            "Use this in Devin's Add Your Own MCP flow when ControlKeel is installed in the runtime."
        },
        pretty: true
      ) <> "\n"
    )

    webhook_path = Path.join(root, "devin/controlkeel-webhook.json")

    File.write!(
      webhook_path,
      Jason.encode!(
        %{
          "events" => ["task.completed", "task.failed", "finding.created", "proof.generated"],
          "note" =>
            "Use this when wiring Devin sessions back into ControlKeel governance or external CI hooks."
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
        %{"path" => config_path, "kind" => "settings"},
        %{"path" => webhook_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Devin can ingest ControlKeel workflow guidance.",
        "Use the custom MCP JSON as the starting point for Devin's Add Your Own MCP flow."
      ]
    )
  end
end
