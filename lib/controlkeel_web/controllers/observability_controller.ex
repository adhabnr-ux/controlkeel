defmodule ControlKeelWeb.ObservabilityController do
  use ControlKeelWeb, :controller

  # TODO: Add `plug ControlKeelWeb.Plugs.RequireSessionAuth` when OAuth/session auth
  # lands (refactor/web-auth). Should mirror LiveAuth.require_cloud_auth: passthrough
  # in local mode, require membership in cloud/self_hosted, verify org ownership of
  # the session's workspace to prevent cross-org data leakage.

  alias ControlKeel.Observability.Telemetry

  def export_session(conn, %{"id" => id}) do
    case Telemetry.export_session(id) do
      {:ok, envelope} ->
        json(conn, envelope)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "session not found"})

      {:error, :invalid_session_id} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "session id must be an integer"})
    end
  end
end
