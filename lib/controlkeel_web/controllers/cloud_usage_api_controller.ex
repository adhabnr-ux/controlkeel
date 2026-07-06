defmodule ControlKeelWeb.CloudUsageApiController do
  @moduledoc """
  Usage API at GET /cloud/v1/orgs/:slug/usage.

  Returns today's spend, the org's monthly budget, and a usage ratio.
  Requires cloud API auth (CloudWorkspaceKeyAuth pipeline). The org slug
  is resolved and cross-checked against the authenticated workspace's org.
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Usage.Meter

  plug ControlKeelWeb.Plugs.CloudWorkspaceKeyAuth

  @doc "GET /cloud/v1/orgs/:slug/usage"
  def show(conn, %{"slug" => slug}) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "organization_not_found"})

      org ->
        # Verify the authenticated workspace belongs to this org
        ws_org_id = conn.assigns[:db_workspace_org_id] || conn.assigns[:db_org_id]

        if ws_org_id && ws_org_id == org.id do
          spend_cents = Meter.usage_today(org.id)
          budget_cents = Accounts.org_budget_cents(org) || 0
          ratio = if budget_cents > 0, do: Float.round(spend_cents / budget_cents, 4), else: 0.0

          json(conn, %{
            org_id: org.id,
            org_slug: org.slug,
            org_name: org.name,
            date: Date.utc_today(),
            spend_cents: spend_cents,
            budget_cents: budget_cents,
            usage_ratio: ratio,
            remaining_cents: max(budget_cents - spend_cents, 0)
          })
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "org_access_denied"})
        end
    end
  end
end
