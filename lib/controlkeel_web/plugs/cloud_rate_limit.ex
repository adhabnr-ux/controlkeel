defmodule ControlKeelWeb.Plugs.CloudRateLimit do
  @moduledoc """
  Per-workspace rate limit for `/cloud/v1` routes that require auth.

  Must run AFTER `CloudWorkspaceKeyAuth` so unauthenticated requests cannot
  burn through a legitimate tenant's bucket. On overflow returns a 429
  response with a `Retry-After` header and a JSON error body.

  If `:db_workspace_id` is missing in assigns (e.g. the plug is mounted on
  a route that doesn't authenticate), the request is passed through —
  CloudWorkspaceKeyAuth would have already halted any unauthenticated
  attempt before this plug runs.
  """

  import Plug.Conn

  alias ControlKeel.Cloud.RateLimiter

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:db_workspace_id] do
      ws_id when is_integer(ws_id) ->
        case RateLimiter.hit(ws_id) do
          :ok ->
            conn

          {:error, :rate_limited, retry_after} ->
            conn
            |> put_resp_header("retry-after", Integer.to_string(retry_after))
            |> put_status(:too_many_requests)
            |> Phoenix.Controller.json(%{error: "rate_limited", retry_after: retry_after})
            |> halt()
        end

      _ ->
        # No workspace context. Let it through — auth plug should have halted earlier.
        conn
    end
  end
end
