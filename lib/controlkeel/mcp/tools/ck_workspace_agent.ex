defmodule ControlKeel.MCP.Tools.CkWorkspaceAgent do
  @moduledoc false

  alias ControlKeel.Governance.WorkspaceAgent
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Utils

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "Workspace agent operation failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    mode = Map.get(arguments, "mode", "list")

    case mode do
      "register" ->
        workspace_id = Arguments.parse_integer(arguments["workspace_id"])

        case workspace_id do
          nil ->
            {:error, {:invalid_arguments, "`workspace_id` is required"}}

          wid ->
            attrs = %{
              workspace_id: wid,
              name: arguments["name"],
              role: arguments["role"] || "specialized",
              agent_type: arguments["agent_type"],
              budget_cents: Arguments.parse_integer(arguments["budget_cents"]) || 0,
              maintainer_id: Arguments.parse_integer(arguments["maintainer_id"]),
              scope: arguments["scope"] || %{},
              policy_overrides: arguments["policy_overrides"] || %{}
            }

            case WorkspaceAgent.register(attrs) do
              {:ok, agent} ->
                {:ok, format_agent(agent)}

              {:error, :primary_exists} ->
                {:error,
                 {:invalid_arguments, "A primary agent already exists for this workspace"}}

              {:error, changeset} ->
                {:error, {:invalid_arguments, Utils.format_changeset_errors(changeset)}}
            end
        end

      "update" ->
        agent_id = Arguments.parse_integer(arguments["agent_id"])

        case agent_id do
          nil ->
            {:error, {:invalid_arguments, "`agent_id` is required"}}

          aid ->
            attrs =
              Map.take(arguments, [
                "name",
                "role",
                "status",
                "scope",
                "budget_cents",
                "policy_overrides",
                "maintainer_id"
              ])
              |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
              |> Map.new()
              |> Map.update(:budget_cents, nil, fn
                nil -> nil
                v -> Arguments.parse_integer(v)
              end)
              |> Map.update(:maintainer_id, nil, fn
                nil -> nil
                v -> Arguments.parse_integer(v)
              end)
              |> Enum.reject(fn {_k, v} -> is_nil(v) end)
              |> Map.new()

            case WorkspaceAgent.update(aid, attrs) do
              {:ok, agent} ->
                {:ok, format_agent(agent)}

              {:error, changeset} ->
                {:error, {:invalid_arguments, Utils.format_changeset_errors(changeset)}}
            end
        end

      "list" ->
        workspace_id = Arguments.parse_integer(arguments["workspace_id"])

        case workspace_id do
          nil ->
            {:error, {:invalid_arguments, "`workspace_id` is required"}}

          wid ->
            agents = WorkspaceAgent.list(wid)
            {:ok, %{"agents" => Enum.map(agents, &format_agent/1), "count" => length(agents)}}
        end

      "health" ->
        agent_id = Arguments.parse_integer(arguments["agent_id"])

        case agent_id do
          nil ->
            {:error, {:invalid_arguments, "`agent_id` is required"}}

          aid ->
            {:ok, WorkspaceAgent.health(aid)}
        end

      "retire" ->
        agent_id = Arguments.parse_integer(arguments["agent_id"])

        case agent_id do
          nil ->
            {:error, {:invalid_arguments, "`agent_id` is required"}}

          aid ->
            case WorkspaceAgent.retire(aid) do
              {:ok, agent} ->
                {:ok, format_agent(agent)}

              {:error, :cannot_retire_primary} ->
                {:error,
                 {:invalid_arguments,
                  "Cannot retire the primary agent. Transfer primary role first."}}
            end
        end

      _ ->
        {:error, {:invalid_arguments, "mode must be register, update, list, health, or retire"}}
    end
  end

  defp format_agent(agent) do
    %{
      "id" => agent.id,
      "external_id" => agent.external_id,
      "workspace_id" => agent.workspace_id,
      "name" => agent.name,
      "role" => agent.role,
      "agent_type" => agent.agent_type,
      "status" => agent.status,
      "scope" => agent.scope,
      "budget_cents" => agent.budget_cents,
      "spent_cents" => agent.spent_cents,
      "maintainer_id" => agent.maintainer_id,
      "sessions_count" => agent.sessions_count,
      "last_active_at" => agent.last_active_at
    }
  end
end
