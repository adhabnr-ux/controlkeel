defmodule ControlKeelWeb.ObservabilityControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  import ControlKeel.MissionFixtures

  alias ControlKeel.Accounts
  alias ControlKeel.Repo

  describe "GET /observability/sessions/:id/export.json (local mode)" do
    test "exports the session envelope without authentication", %{conn: conn} do
      session = session_fixture()

      conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

      body = json_response(conn, :ok)
      assert body["integrity"]["session_id"] == session.id
      assert is_binary(body["integrity"]["payload_sha256"])
    end

    test "returns 404 for an unknown session", %{conn: conn} do
      conn = get(conn, "/observability/sessions/999999/export.json")
      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end
  end

  describe "GET /observability/sessions/:id/export.json (cloud mode)" do
    setup do
      original = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :cloud)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:controlkeel, :runtime_mode)
        else
          Application.put_env(:controlkeel, :runtime_mode, original)
        end
      end)

      :ok
    end

    setup %{conn: conn} do
      {:ok, org} =
        Accounts.create_org(%{name: "Acme", slug: "acme-#{System.unique_integer([:positive])}"})

      {:ok, user} =
        Accounts.create_user(%{email: "acme-#{System.unique_integer([:positive])}@example.com"})

      %Accounts.Membership{}
      |> Accounts.Membership.changeset(%{
        user_id: user.id,
        org_id: org.id,
        role: "admin",
        status: "active"
      })
      |> Repo.insert!()

      workspace = workspace_fixture(%{org_id: org.id})
      session = session_fixture(%{workspace: workspace})

      conn = init_test_session(conn, %{current_user_id: user.id, current_org_id: org.id})

      {:ok, conn: conn, org: org, user: user, workspace: workspace, session: session}
    end

    test "unauthenticated requests are rejected with 401", %{session: session} do
      conn = build_conn()
      conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

      assert json_response(conn, :unauthorized) == %{"error" => "sign in required"}
    end

    test "authenticated requests for own-org sessions export the envelope", %{
      conn: conn,
      session: session
    } do
      conn = get(conn, ~p"/observability/sessions/#{session.id}/export.json")

      body = json_response(conn, :ok)
      assert body["integrity"]["session_id"] == session.id
    end

    test "sessions from another org are not exportable", %{conn: conn} do
      {:ok, outsider_org} =
        Accounts.create_org(%{
          name: "Outsider",
          slug: "outsider-#{System.unique_integer([:positive])}"
        })

      outsider_workspace = workspace_fixture(%{org_id: outsider_org.id})
      outsider_session = session_fixture(%{workspace: outsider_workspace})

      conn = get(conn, ~p"/observability/sessions/#{outsider_session.id}/export.json")

      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end

    test "unknown sessions return 404 for authenticated users", %{conn: conn} do
      conn = get(conn, "/observability/sessions/999999/export.json")
      assert json_response(conn, :not_found) == %{"error" => "session not found"}
    end
  end
end
