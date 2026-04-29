defmodule ControlKeelWeb.ObservabilityController do
  use ControlKeelWeb, :controller

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
