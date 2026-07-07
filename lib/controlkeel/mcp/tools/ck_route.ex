defmodule ControlKeel.MCP.Tools.CkRoute do
  @moduledoc false

  alias ControlKeel.Agent.Router
  alias ControlKeel.Utils

  @doc """
  MCP tool: ck_route

  Recommends the best agent for a given task description, considering
  security tier, budget, and task type.

  Arguments:
  - `task` (required) — plain-language task description
  - `risk_tier` (optional) — "low" | "medium" | "high" | "critical"
  - `budget_remaining_cents` (optional) — remaining budget in cents
  - `allowed_agents` (optional) — list of agent IDs to restrict routing to
  """
  def call(arguments) when is_map(arguments) do
    task = Map.get(arguments, "task", "")

    opts =
      []
      |> maybe_put(:risk_tier, Map.get(arguments, "risk_tier"))
      |> maybe_put(:budget_remaining_cents, Map.get(arguments, "budget_remaining_cents"))
      |> maybe_put(:allowed_agents, Map.get(arguments, "allowed_agents"))
      |> maybe_put(:token_overhead_k, Map.get(arguments, "token_overhead_k"))

    case Router.route(task, opts) do
      {:ok, recommendation} ->
        {:ok, Utils.stringify_keys_deep_list(recommendation)}

      {:error, :no_suitable_agent, message} ->
        {:error, {:policy_violation, message}}
    end
  end

  def call(_), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
