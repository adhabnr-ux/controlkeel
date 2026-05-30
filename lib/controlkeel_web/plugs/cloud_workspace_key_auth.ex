defmodule ControlKeelWeb.Plugs.CloudWorkspaceKeyAuth do
  @moduledoc """
  Pipeline-level auth for /cloud/v1 routes that require a workspace-scoped
  Bearer token.

  On success assigns:
    - `:cloud_workspace_id`    — the string UUID from the token claims
    - `:db_workspace_id`       — the integer Mission.Workspace.id from WorkspaceKeyRegistry
    - `:db_workspace_org_id`   — the owning org id when available

  Returns 401 on missing/invalid Bearer, 404 when the workspace_id has no
  enrolled key mapping on this node.

  Routes that are intentionally unauthenticated at the HTTP level (e.g.
  `/cloud/v1/workspaces/register`) must NOT go through this pipeline.
  """

  import Plug.Conn

  alias ControlKeel.Cloud.AuthToken
  alias ControlKeel.Cloud.WorkspaceKeyRegistry
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    with [bearer] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- bearer,
         {:ok, %{workspace_id: ws_id}} <- AuthToken.verify(token),
         {:ok, key} <- WorkspaceKeyRegistry.fetch(ws_id),
         %{mission_workspace_id: db_id} <- key,
         true <- is_integer(db_id) do
      org_id = key.org_id || workspace_org_id(db_id)

      conn
      |> assign(:cloud_workspace_id, ws_id)
      |> assign(:db_workspace_id, db_id)
      |> assign(:db_workspace_org_id, org_id)
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> Phoenix.Controller.json(%{error: "workspace not enrolled on this node"})
        |> halt()

      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "unauthorized"})
        |> halt()
    end
  end

  defp workspace_org_id(db_id) when is_integer(db_id) do
    case Repo.get(Workspace, db_id) do
      %Workspace{org_id: org_id} -> org_id
      nil -> nil
    end
  end
end
