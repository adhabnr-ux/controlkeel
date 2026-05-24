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
        "proof_refs": ["hash1", ...]  // optional
      }

  Auth is the single-use callback token issued at handoff time. The token is
  bound to one specific run package; tokens for terminal packages are rejected
  so a late callback can't overwrite recorded evidence.

  Responses:

    - `200 OK` with the updated package summary
    - `400 Bad Request` on malformed body or invalid status
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
         {:ok, package} <- authenticate(token),
         {:ok, updated} <- transition(package, status, params) do
      conn
      |> put_status(:ok)
      |> json(summary(updated))
    else
      {:error, :missing_bearer} ->
        conn |> put_status(:unauthorized) |> json(%{error: "missing_or_invalid_bearer"})

      {:error, :invalid_status} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_status"})

      {:error, :missing_status} ->
        conn |> put_status(:bad_request) |> json(%{error: "missing_status"})

      {:error, :token_not_found} ->
        conn |> put_status(:forbidden) |> json(%{error: "invalid_token"})

      {:error, {:terminal, package}} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "package_is_terminal", status: package.status})

      {:error, :transition_terminal} ->
        conn |> put_status(:conflict) |> json(%{error: "package_already_terminal"})

      {:error, reason} ->
        conn |> put_status(:bad_request) |> json(%{error: inspect(reason)})
    end
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

  defp summary(package) do
    %{
      id: package.id,
      status: package.status,
      runtime_target: package.runtime_target,
      dispatched_at: package.dispatched_at && DateTime.to_iso8601(package.dispatched_at),
      completed_at: package.completed_at && DateTime.to_iso8601(package.completed_at),
      result_summary: package.result_summary,
      error_summary: package.error_summary,
      proof_refs: package.proof_refs
    }
  end
end
