defmodule ControlKeel.CLI.Capabilities do
  @moduledoc false

  alias ControlKeel.Agent.Integration
  alias ControlKeel.CLI.Catalog

  def payload do
    entries = Catalog.all()

    %{
      "commands" => Enum.map(entries, &command_payload/1),
      "families" => family_payload(entries),
      "hosts" => Enum.map(Integration.attach_catalog(), &host_payload/1),
      "mcp_tools" => unique_catalog_values(entries, :related_mcp_tools),
      "skills" => unique_catalog_values(entries, :related_skills),
      "hooks" => unique_catalog_values(entries, :related_hooks),
      "plugins" => unique_catalog_values(entries, :related_plugins),
      "automation" => %{
        "json_capable_commands" => count_output(entries, :json),
        "file_output_commands" => count_output(entries, :file),
        "dry_run_capable_commands" => Enum.count(entries, & &1.safety.dry_run),
        "read_only_commands" => Enum.count(entries, &(not &1.safety.mutates)),
        "mutating_commands" => Enum.count(entries, & &1.safety.mutates),
        "host_count" => length(Integration.attach_catalog())
      }
    }
  end

  def lines(payload) do
    automation = payload["automation"]

    [
      "ControlKeel capabilities",
      "Commands: #{length(payload["commands"])} across #{length(payload["families"])} families",
      "Hosts: #{length(payload["hosts"])} attachable integrations",
      "MCP tools linked: #{length(payload["mcp_tools"])}",
      "Skills linked: #{length(payload["skills"])}",
      "Hooks linked: #{length(payload["hooks"])}",
      "Plugins linked: #{length(payload["plugins"])}",
      "JSON-capable commands: #{automation["json_capable_commands"]}",
      "Read-only commands: #{automation["read_only_commands"]}",
      "Mutating commands: #{automation["mutating_commands"]}",
      "For machine-readable details: controlkeel capabilities --json"
    ]
  end

  defp command_payload(entry) do
    %{
      "command" => Atom.to_string(entry.command),
      "path" => entry.path,
      "family" => Atom.to_string(entry.family),
      "summary" => entry.summary,
      "examples" => entry.examples,
      "inputs" => Enum.map(entry.inputs, &to_string/1),
      "outputs" => Enum.map(entry.outputs, &to_string/1),
      "safety" => stringify_key_map(entry.safety),
      "related_mcp_tools" => entry.related_mcp_tools,
      "related_skills" => entry.related_skills,
      "related_hooks" => entry.related_hooks,
      "related_plugins" => entry.related_plugins,
      "help_topic" => entry.help_topic
    }
  end

  defp family_payload(entries) do
    entries
    |> Enum.group_by(& &1.family)
    |> Enum.map(fn {family, family_entries} ->
      %{
        "family" => Atom.to_string(family),
        "command_count" => length(family_entries),
        "commands" => Enum.map(family_entries, &Atom.to_string(&1.command))
      }
    end)
    |> Enum.sort_by(& &1["family"])
  end

  defp host_payload(integration) do
    %{
      "id" => integration.id,
      "label" => integration.label,
      "category" => integration.category,
      "support_class" => integration.support_class,
      "attach_command" => integration.attach_command,
      "preferred_target" => integration.preferred_target,
      "default_scope" => integration.default_scope,
      "supported_scopes" => integration.supported_scopes,
      "mcp_mode" => integration.mcp_mode,
      "skills_mode" => integration.skills_mode,
      "auth_mode" => integration.auth_mode,
      "provider_bridge" => stringify_key_map(integration.provider_bridge || %{}),
      "export_targets" => integration.export_targets,
      "artifact_surfaces" => integration.artifact_surfaces
    }
  end

  defp unique_catalog_values(entries, key) do
    entries
    |> Enum.flat_map(&Map.get(&1, key, []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp count_output(entries, output), do: Enum.count(entries, &(output in &1.outputs))

  defp stringify_key_map(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp stringify_key_map(_), do: %{}
end
