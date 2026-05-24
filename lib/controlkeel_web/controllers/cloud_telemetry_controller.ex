defmodule ControlKeelWeb.CloudTelemetryController do
  @moduledoc """
  HTTP entry point for cloud telemetry batches.

  Wire protocol matches `ControlKeel.Cloud.Sender`:

      POST /cloud/v1/telemetry
      Authorization: Bearer <workspace_id>
      Content-Type: application/json

      { "schema_version": "1", "workspace_id": "ws_...", "events": [...] }

  Authorization is currently a placeholder Bearer token containing the
  workspace_id. A follow-up slice will replace this with a workspace-keypair-
  signed token verified against the registered public key.

  Response:

    - `202 Accepted` with `{"accepted":N, "duplicates":N, "rejected":N, "outcomes":[...]}`
    - `400 Bad Request` on malformed batch / schema mismatch / empty batch
    - `401 Unauthorized` on missing or invalid Bearer token
    - `403 Forbidden` when the Bearer token's workspace_id does not match the batch
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Cloud.AuthToken
  alias ControlKeel.Cloud.Ingestion

  def ingest(conn, params) do
    with {:ok, token} <- extract_bearer(conn),
         {:ok, claims} <- verify_bearer(token) do
      case Ingestion.ingest(params, claims.workspace_id) do
        {:ok, summary} ->
          conn
          |> put_status(:accepted)
          |> json(%{
            accepted: summary.accepted,
            duplicates: summary.duplicates,
            rejected: summary.rejected,
            outcomes: summary.outcomes
          })

        {:error, :workspace_mismatch} ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "workspace_mismatch"})

        {:error, reason} ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: Atom.to_string(reason)})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: Atom.to_string(reason)})
    end
  end

  defp extract_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when token != "" -> {:ok, token}
      ["bearer " <> token | _] when token != "" -> {:ok, token}
      _ -> {:error, :missing_or_invalid_bearer}
    end
  end

  defp verify_bearer(token) do
    case AuthToken.verify(token) do
      {:ok, _claims} = ok -> ok
      {:error, _reason} -> {:error, :invalid_token}
    end
  end
end
