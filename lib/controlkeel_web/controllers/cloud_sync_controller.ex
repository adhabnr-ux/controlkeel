defmodule ControlKeelWeb.CloudSyncController do
  @moduledoc """
  Handles bidirectional cloud sync requests.

  Two actions:
    - push: receives a batch of local records from an enrolled workspace
    - pull: returns records for a workspace since a given timestamp
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Cloud.{AuthToken, Sync}
  alias ControlKeel.Repo

  plug :verify_sync_token when action in [:push, :pull]

  @max_batch_size 500

  def push(conn, %{"records" => records, "workspace_id" => ws_id}) do
    workspace_id = conn.assigns[:sync_workspace_id]

    if ws_id != workspace_id do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "workspace_id mismatch"})
    else
      if length(records) > @max_batch_size do
        conn
        |> put_status(:bad_request)
        |> json(%{error: "batch too large", max: @max_batch_size})
      else
        result = Sync.upsert_batch(records)

        conn
        |> json(%{
          accepted: result.total,
          inserted: result.inserted,
          updated: result.updated,
          skipped: result.skipped,
          conflicts: result.conflicts
        })
      end
    end
  end

  def push(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing records or workspace_id"})
  end

  def pull(conn, %{"since" => since_iso, "workspace_id" => ws_id}) do
    workspace_id = conn.assigns[:sync_workspace_id]

    if ws_id != workspace_id do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "workspace_id mismatch"})
    else
      since = parse_timestamp(since_iso)

      records = collect_since(workspace_id, since)

      conn
      |> json(%{records: records, total: length(records)})
    end
  end

  def pull(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing since or workspace_id"})
  end

  # ── Auth plug ───────────────────────────────────────────────────────

  defp verify_sync_token(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case AuthToken.verify(token) do
          {:ok, %{ws: workspace_id}} ->
            assign(conn, :sync_workspace_id, workspace_id)

          {:error, reason} ->
            conn
            |> put_status(:unauthorized)
            |> json(%{error: "invalid token", reason: to_string(reason)})
            |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "missing authorization header"})
        |> halt()
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp collect_since(workspace_id, since) do
    import Ecto.Query

    alias ControlKeel.Mission.{Session, Finding}

    session_ids =
      Session
      |> where([s], s.workspace_id == ^workspace_id)
      |> select([s], s.id)
      |> Repo.all()

    if session_ids == [] do
      []
    else
      # Collect recently synced records that the requester doesn't have
      Finding
      |> where([f], f.session_id in ^session_ids)
      |> where([f], f.synced_at > ^since)
      |> where([f], not is_nil(f.external_id))
      |> limit(500)
      |> Repo.all()
      |> Enum.map(&Sync.serialize_record({"finding", &1}))
    end
  end

  defp parse_timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now() |> DateTime.add(-3600, :second)
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now() |> DateTime.add(-3600, :second)
end
