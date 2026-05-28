defmodule ControlKeelWeb.CloudSyncControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Cloud.AuthToken
  alias ControlKeel.Cloud.WorkspaceIdentity

  setup %{conn: conn} do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-sync-ctrl-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    {:ok, identity, :created} = WorkspaceIdentity.ensure()
    {:ok, token} = AuthToken.sign(identity)

    conn = put_req_header(conn, "content-type", "application/json")

    {:ok, conn: conn, identity: identity, token: token}
  end

  describe "POST /cloud/v1/sync/push" do
    test "rejects missing Authorization header", %{conn: conn} do
      conn = post(conn, "/cloud/v1/sync/push", %{})
      assert response(conn, 401)
    end

    test "rejects invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid-token")
        |> post("/cloud/v1/sync/push", %{})

      assert response(conn, 401)
    end

    test "accepts valid token with empty records", %{conn: conn, token: token, identity: identity} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/sync/push", %{
          workspace_id: identity.workspace_id,
          records: []
        })

      assert response(conn, 200)
      body = json_response(conn, 200)
      assert body["accepted"] == 0
    end

    test "rejects payload exceeding batch limit", %{conn: conn, token: token, identity: identity} do
      oversized =
        Enum.map(1..501, fn i ->
          %{"external_id" => "f_#{i}", "kind" => "finding", "payload" => %{}}
        end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/sync/push", %{
          workspace_id: identity.workspace_id,
          records: oversized
        })

      assert response(conn, 400)
    end
  end

  describe "POST /cloud/v1/sync/pull" do
    test "rejects missing Authorization header", %{conn: conn} do
      conn = post(conn, "/cloud/v1/sync/pull", %{})
      assert response(conn, 401)
    end

    test "accepts valid token with since parameter", %{
      conn: conn,
      token: token,
      identity: identity
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/sync/pull", %{
          workspace_id: identity.workspace_id,
          since: DateTime.utc_now() |> DateTime.to_iso8601()
        })

      assert response(conn, 200)
      body = json_response(conn, 200)
      assert is_list(body["records"])
    end
  end
end
