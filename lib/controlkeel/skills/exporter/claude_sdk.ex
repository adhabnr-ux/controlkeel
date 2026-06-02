defmodule ControlKeel.Skills.Exporter.ClaudeSdk do
  @moduledoc false

  alias ControlKeel.Skills.Exporter, as: E

  def write(root, project_root, _skills, opts) do
    ts_dir = Path.join(root, "typescript")
    py_dir = Path.join(root, "python")
    File.mkdir_p!(ts_dir)
    File.mkdir_p!(py_dir)

    ts_path = Path.join(ts_dir, "ck_agent.ts")
    ts_plugin_path = Path.join(ts_dir, "ck_plugin_agent.ts")
    py_path = Path.join(py_dir, "ck_agent.py")

    File.write!(ts_path, E.claude_sdk_typescript_contents())
    File.write!(ts_plugin_path, E.claude_sdk_typescript_plugin_contents())
    File.write!(py_path, E.claude_sdk_python_contents())

    mcp_path = Path.join(root, ".mcp.json")
    File.write!(mcp_path, Jason.encode!(E.mcp_payload(project_root, opts), pretty: true) <> "\n")

    E.with_common_assets(
      root,
      project_root,
      opts,
      [
        %{"path" => ts_path, "kind" => "sdk"},
        %{"path" => ts_plugin_path, "kind" => "sdk"},
        %{"path" => py_path, "kind" => "sdk"},
        %{"path" => mcp_path, "kind" => "mcp"}
      ],
      [
        "Copy `typescript/ck_agent.ts` or `python/ck_agent.py` into your SDK project as a governed agent starting point.",
        "Set `settingSources: [\"user\", \"project\"]` (TypeScript) or `setting_sources=[\"user\", \"project\"]` (Python) so the SDK discovers CK skills, agents, and hooks from the filesystem.",
        "Add `allowedTools: [\"Skill\", \"mcp__controlkeel__*\"]` (or `\"*\"`) to enable CK MCP tools and skill invocations in the SDK.",
        "Use `typescript/ck_plugin_agent.ts` to load the full CK claude-plugin bundle via the `plugins` option — E.export the claude-plugin target first.",
        "WARNING: `settingSources: []` disables filesystem discovery and bypasses CK lifecycle hooks — avoid in governed production deployments.",
        "The `excludeDynamicSections: true` SDK option enables prompt caching across machines; if the CK system prompt varies per session, leave it unset.",
        "Use .mcp.json for the MCP server reference; wire it via `mcpServers` in SDK options rather than relying on a settings file in headless environments."
      ]
    )
  end
end
