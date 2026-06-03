defmodule ControlKeel.MCP.Tools.CkAttach do
  @moduledoc """
  MCP tool: ck_attach

  Closes the gap for users who installed ControlKeel via a one-line copy-paste
  MCP-add command (Claude `mcp add-json`, Cursor deeplink, etc.) instead of
  running `controlkeel attach <host>`. Those users get the tool surface but
  miss the host-specific artifacts:

    - SessionStart / PreToolUse / PostToolUse / UserPromptSubmit hooks
    - Skills (`.claude/skills`, `.codex/skills`, `.agents/skills`)
    - Slash commands (e.g. `/controlkeel-completion-review`)
    - `AGENTS.md` / `CLAUDE.md` governance preamble
    - Subagent profiles (where applicable)

  This tool runs the same machinery as `controlkeel attach <host>` from
  inside the MCP session. Idempotent — re-running on a fully attached
  project just refreshes artifacts to the current version.

  ## Arguments

    - `host` (required): one of the attachable agent IDs. Use
      `ck_attach` error output to see the supported host IDs.
    - `project_root` (optional): absolute path to the project. Defaults to
      `CK_PROJECT_ROOT` or the MCP server's working directory.
    - `scope` (optional): `"project"` (default) or `"user"`. Forwarded to
      the host's attach command where applicable.

  ## Trust boundary

  This tool writes files within `project_root` (hooks, skills, MCP config,
  AGENTS.md). It does not run network egress and does not touch state
  outside the project root. Same trust class as any MCP write tool.
  """

  alias ControlKeel.AgentIntegration
  alias ControlKeel.CLI

  def call(arguments) when is_map(arguments) do
    with {:ok, host} <- require_host(arguments),
         {:ok, _integration} <- validate_host(host) do
      options =
        []
        |> maybe_put(:project_root, Map.get(arguments, "project_root"))
        |> Keyword.put(:scope, Map.get(arguments, "scope", "project"))

      command = %{
        command: :attach,
        args: [host],
        options: Enum.into(options, %{})
      }

      case CLI.run_command(command, Map.get(arguments, "project_root")) do
        {:ok, lines} ->
          {:ok,
           %{
             "host" => host,
             "status" => "attached",
             "lines" => lines,
             "next_steps" => next_steps()
           }}

        {:error, message} ->
          {:error, {:invalid_arguments, message}}
      end
    end
  end

  def call(_), do: {:error, {:invalid_arguments, "arguments must be a JSON object"}}

  defp require_host(%{"host" => host}) when is_binary(host) and host != "" do
    {:ok, host}
  end

  defp require_host(_), do: {:error, {:invalid_arguments, "host is required"}}

  defp validate_host(host) do
    attachable = AgentIntegration.attachable_ids()

    cond do
      host not in attachable ->
        {:error,
         {:invalid_arguments, "unknown host: #{host}. Supported: #{Enum.join(attachable, ", ")}"}}

      AgentIntegration.get(host) == nil ->
        {:error, {:invalid_arguments, "host #{host} is not in the integration catalog"}}

      true ->
        {:ok, AgentIntegration.get(host)}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp next_steps do
    [
      "Run ck_context to load mission state.",
      "Optional: controlkeel cloud connect --enroll https://controlkeel.com",
      "Verify: controlkeel cloud doctor"
    ]
  end

  @doc """
  List of host IDs this tool can attach — the canonical attach-client set from
  AgentIntegration, so the agent-facing ck_attach surface never drifts below the
  hosts the CLI actually attaches.
  """
  def attachable_hosts, do: AgentIntegration.attachable_ids()
end
