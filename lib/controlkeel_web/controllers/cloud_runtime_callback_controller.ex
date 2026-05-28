defmodule ControlKeelWeb.CloudRuntimeCallbackController do
  @moduledoc """
  HTTP callback endpoint for downstream cloud runtimes (Devin, Open SWE,
  Cursor Cloud Agents, Replit Agent, Warp Oz, etc.) executing a
  ControlKeel-issued run package.

  Wire protocol:

      POST /cloud/v1/runtime/callbacks
      Authorization: Bearer <raw_callback_token>
      Content-Type: application/json

      {
        "status": "in_progress" | "completed" | "failed" | "cancelled",
        "result_summary": "...",      // optional
        "error_summary": "...",       // optional
        "proof_refs": ["hash1", ...], // optional
        "findings": [                 // optional — persisted on the
          {                           //   originating session, tagged with
            "title": "...",           //   {source: cloud_runtime_callback,
            "severity": "high",       //    cloud_package_id, runtime_target}
            "category": "security",
            "rule_id": "...",
            "plain_message": "..."
          }
        ]
      }

  Auth is the callback token issued at handoff time. The token is bound to
  one specific run package and remains valid until the package reaches a
  terminal status, after which late callbacks are rejected so they can't
  overwrite recorded evidence.

  Responses:

    - `200 OK` with the updated package summary (and `findings_created`
      when findings were posted)
    - `400 Bad Request` on malformed body, invalid status, or malformed
      finding entries
    - `401 Unauthorized` on missing Bearer
    - `403 Forbidden` on unknown / terminal token
    - `409 Conflict` if status transition rejects (rare race)
  """

  use ControlKeelWeb, :controller

  alias ControlKeel.Cloud.RunPackage
  alias ControlKeel.Cloud.RuntimeContext

  def update(conn, params) do
    with {:ok, token} <- extract_bearer(conn),
         {:ok, status} <- extract_status(params),
         {:ok, findings} <- extract_findings(params),
         {:ok, package} <- authenticate(token),
         {:ok, updated} <- transition(package, status, params),
         {:ok, finding_ids} <- RuntimeContext.ingest_findings(updated, findings) do
      conn
      |> put_status(:ok)
      |> json(summary(updated, finding_ids))
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing_or_invalid_bearer"})

      {:error, :invalid_status} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_status"})

      {:error, :missing_status} ->
        conn |> put_status(:bad_request) |> json(%{error: "missing_status"})

      {:error, :invalid_findings} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_findings"})

      {:error, :token_not_found} ->
        conn |> put_status(:forbidden) |> json(%{error: "invalid_token"})

      {:error, {:terminal, package}} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "package_is_terminal", status: package.status})

      {:error, :transition_terminal} ->
        conn |> put_status(:conflict) |> json(%{error: "package_already_terminal"})

      {:error, {%Ecto.Changeset{} = cs, idx}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "finding_invalid", index: idx, details: format_changeset(cs)})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
  end

  defp extract_findings(%{"findings" => nil}), do: {:ok, []}
  defp extract_findings(params) when not is_map_key(params, "findings"), do: {:ok, []}

  defp extract_findings(%{"findings" => list}) when is_list(list) do
    if Enum.all?(list, &is_map/1), do: {:ok, list}, else: {:error, :invalid_findings}
  end

  defp extract_findings(_), do: {:error, :invalid_findings}

  defp format_changeset(%Ecto.Changeset{errors: errors}) do
    Enum.map(errors, fn {field, {message, _opts}} -> "#{field}: #{message}" end)
  end

  defp extract_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] when token != "" -> {:ok, token}
      ["bearer " <> token | _] when token != "" -> {:ok, token}
      _ -> {:error, :missing_bearer}
    end
  end

  defp extract_status(%{"status" => status}) when is_binary(status) do
    if status in RunPackage.valid_statuses(), do: {:ok, status}, else: {:error, :invalid_status}
  end

  defp extract_status(_), do: {:error, :missing_status}

  defp authenticate(token) do
    case RuntimeContext.authenticate_callback(token) do
      {:ok, package} -> {:ok, package}
      :not_found -> {:error, :token_not_found}
      {:terminal, package} -> {:error, {:terminal, package}}
    end
  end

  defp transition(package, status, params) do
    opts =
      []
      |> maybe_put(:result_summary, Map.get(params, "result_summary"))
      |> maybe_put(:error_summary, Map.get(params, "error_summary"))
      |> maybe_put(:proof_refs, Map.get(params, "proof_refs"))

    case RuntimeContext.transition_status(package, status, opts) do
      {:ok, updated} -> {:ok, updated}
      {:error, :terminal} -> {:error, :transition_terminal}
      {:error, :invalid_status} -> {:error, :invalid_status}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp summary(package, finding_ids \\ []) do
    %{
      id: package.id,
      external_id: package.external_id,
      status: package.status,
      runtime_target: package.runtime_target,
      dispatched_at: package.dispatched_at && DateTime.to_iso8601(package.dispatched_at),
      completed_at: package.completed_at && DateTime.to_iso8601(package.completed_at),
      result_summary: package.result_summary,
      error_summary: package.error_summary,
      proof_refs: package.proof_refs,
      findings_created: finding_ids
    }
  end
end
