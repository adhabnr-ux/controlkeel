defmodule ControlKeel.Governance.WorkspaceAgent do
  @moduledoc """
  Manages workspace agent roles: primary, specialized, ephemeral.

  Every company has one "super-agent" (primary) maintained by a forward-deployed
  engineer. Specialized agents handle specific domains. Ephemeral agents are
  short-lived task runners.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Repo
  alias ControlKeel.Mission.WorkspaceAgent, as: WorkspaceAgentSchema

  def register(attrs) do
    if attrs[:role] == "primary" or attrs["role"] == "primary" do
      workspace_id = attrs[:workspace_id] || attrs["workspace_id"]

      existing_primary =
        WorkspaceAgentSchema
        |> where([a], a.workspace_id == ^workspace_id and a.role == "primary")
        |> where([a], a.status != "retired")
        |> Repo.all()

      if existing_primary != [] do
        {:error, :primary_exists}
      else
        do_create(attrs)
      end
    else
      do_create(attrs)
    end
  end

  defp do_create(attrs) do
    %WorkspaceAgentSchema{}
    |> WorkspaceAgentSchema.changeset(attrs)
    |> Repo.insert()
  end

  def update(agent_id, attrs) do
    agent = Repo.get!(WorkspaceAgentSchema, agent_id)

    agent
    |> WorkspaceAgentSchema.changeset(attrs)
    |> Repo.update()
  end

  def list(workspace_id, opts \\ []) do
    status_filter = Keyword.get(opts, :status)

    query =
      WorkspaceAgentSchema
      |> where([a], a.workspace_id == ^workspace_id)

    query =
      if status_filter do
        where(query, [a], a.status == ^status_filter)
      else
        query
      end

    query
    |> order_by([a], asc: a.role, asc: a.name)
    |> Repo.all()
  end

  def health(agent_id) do
    agent = Repo.get!(WorkspaceAgentSchema, agent_id)

    budget_utilization =
      if agent.budget_cents > 0 do
        Float.round(agent.spent_cents / agent.budget_cents * 100, 1)
      else
        0.0
      end

    status =
      cond do
        agent.status == "retired" -> "retired"
        agent.status == "paused" -> "paused"
        budget_utilization > 90 -> "over_budget"
        agent.sessions_count == 0 -> "idle"
        true -> "healthy"
      end

    %{
      agent_id: agent.id,
      name: agent.name,
      role: agent.role,
      status: agent.status,
      health_status: status,
      budget_utilization_percent: budget_utilization,
      sessions_count: agent.sessions_count,
      last_active_at: agent.last_active_at
    }
  end

  def retire(agent_id) do
    agent = Repo.get!(WorkspaceAgentSchema, agent_id)

    if agent.role == "primary" do
      {:error, :cannot_retire_primary}
    else
      agent
      |> WorkspaceAgentSchema.changeset(%{status: "retired"})
      |> Repo.update()
    end
  end
end
