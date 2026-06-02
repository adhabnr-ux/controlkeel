defmodule ControlKeel.Skills.Exporter.VirtualBashRuntime do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    agents_path = Path.join(root, "AGENTS.md")
    File.write!(agents_path, E.instructions_only_contents("virtual-bash", project_root, opts))

    readme_path = Path.join(root, "virtual-bash/README.md")
    File.mkdir_p!(Path.dirname(readme_path))
    File.write!(readme_path, E.virtual_bash_runtime_contents(project_root, opts))

    manifest_path = Path.join(root, "virtual-bash/controlkeel-runtime.json")

    File.write!(
      manifest_path,
      Jason.encode!(
        %{
          "mode" => "virtual_workspace_runtime",
          "discovery" => %{
            "transport" => "mcp",
            "command" => E.mcp_command(project_root, opts),
            "args" => E.mcp_args(project_root, opts),
            "tools" => ["ck_fs_ls", "ck_fs_read", "ck_fs_find", "ck_fs_grep"]
          },
          "mutation" => %{
            "surface" => "shell_fallback",
            "approved_for" => ["repo mutation", "package commands", "test execution"],
            "sandbox_adapters" =>
              Enum.map(ControlKeel.ExecutionSandbox.supported_adapters(), fn adapter ->
                Map.take(adapter, [:id, :name, :available])
              end)
          },
          "note" =>
            "Use the virtual workspace first for discovery. Treat shell as a governed fallback, not the primary context surface."
        },
        pretty: true
      ) <> "\n"
    )

    shell_path = Path.join(root, "virtual-bash/controlkeel-shell.example.sh")

    File.write!(shell_path, """
    #!/usr/bin/env bash
    set -euo pipefail

    PROJECT_ROOT="#{Path.expand(project_root)}"

    echo "ControlKeel virtual-bash runtime bootstrap"
    echo "Project root: ${PROJECT_ROOT}"
    echo "Discovery first: use ck_fs_ls, ck_fs_read, ck_fs_find, and ck_fs_grep over MCP."
    echo "Shell fallback: use ControlKeel's configured sandbox for repo mutation, package commands, and tests."
    echo
    echo "MCP server:"
    echo "  #{E.mcp_command(project_root, opts)} #{Enum.join(E.mcp_args(project_root, opts), " ")}"
    echo
    echo "Sandbox adapters:"
    controlkeel sandbox status
    """)

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => agents_path, "kind" => "instructions"},
        %{"path" => readme_path, "kind" => "runtime"},
        %{"path" => manifest_path, "kind" => "runtime"},
        %{"path" => shell_path, "kind" => "runtime"}
      ],
      [
        "Place `AGENTS.md` at the repo root so virtual-bash loops inherit ControlKeel workflow guidance.",
        "Use the runtime manifest for discovery-first orchestration and the shell example when you need governed fallback execution."
      ]
    )
  end
end
