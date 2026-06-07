defmodule ControlKeel.Skills.Exporter.ExecutorRuntime do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("executor", project_root, opts))

    readme_path = Path.join(root, "executor/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.executor_runtime_contents(project_root, opts))

    sources_path = Path.join(root, "executor/controlkeel-sources.example.ts")

    File.write!(sources_path, """
    // Executor bootstrap example
    // Run with: executor call --file controlkeel-sources.example.ts
    return await tools.executor.sources.add({
      kind: "mcp",
      name: "ControlKeel",
      command: "#{E.mcp_command(project_root, opts)}",
      args: #{Jason.encode!(E.mcp_args(project_root, opts))}
    })
    """)

    webhook_path = Path.join(root, "executor/controlkeel-webhook.json")

    File.write!(
      webhook_path,
      Jason.encode!(
        %{
          "events" => ["task.completed", "task.failed", "finding.created", "proof.generated"],
          "note" =>
            "Use this when syncing paused approvals, auth resumes, and governed runtime completions back into ControlKeel."
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
        %{"path" => sources_path, "kind" => "runtime"},
        %{"path" => webhook_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so Executor-driven runs inherit ControlKeel workflow guidance.",
        "Use the runtime README and source example when wiring OpenAPI, GraphQL, MCP, and custom JS integrations into Executor."
      ]
    )
  end
end
