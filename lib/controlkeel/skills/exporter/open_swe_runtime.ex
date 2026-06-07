defmodule ControlKeel.Skills.Exporter.OpenSweRuntime do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("open-swe", project_root, opts))

    readme_path = Path.join(root, "open-swe/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.open_swe_runtime_contents(project_root, opts))

    webhook_path = Path.join(root, "open-swe/controlkeel-webhook.json")

    File.write!(
      webhook_path,
      Jason.encode!(
        %{
          "events" => ["task.completed", "task.failed", "finding.created", "proof.generated"],
          "note" => "Wire this into Open SWE GitHub, Slack, or Linear flows as needed."
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
        %{"path" => webhook_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Open SWE can read ControlKeel guidance.",
        "Use the runtime README and webhook example when wiring GitHub, Slack, or Linear entry points."
      ]
    )
  end
end
