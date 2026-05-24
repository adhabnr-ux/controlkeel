defmodule ControlKeelWeb.CloudRuntimeCallbackControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.MissionFixtures

  setup %{conn: conn} do
    workspace = MissionFixtures.workspace_fixture()
    session = MissionFixtures.session_fixture(%{workspace: workspace})
    task = MissionFixtures.task_fixture(%{session: session})

    {:ok, package, token} =
      RuntimeContext.create_package(%{
        workspace_id: workspace.id,
        session_id: session.id,
        task_id: task.id,
        runtime_target: "devin",
        budget_cents_allocated: 100
      })

    conn = put_req_header(conn, "content-type", "application/json")
    {:ok, conn: conn, workspace: workspace, package: package, token: token}
  end

  describe "POST /cloud/v1/runtime/callbacks auth" do
    test "rejects missing Authorization header", %{conn: conn} do
      conn = post(conn, "/cloud/v1/runtime/callbacks", status: "in_progress")
      assert json_response(conn, 401)["error"] == "missing_or_invalid_bearer"
    end

    test "rejects unknown Bearer token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer nope-not-real")
        |> post("/cloud/v1/runtime/callbacks", status: "in_progress")

      assert json_response(conn, 403)["error"] == "invalid_token"
    end
  end

  describe "POST /cloud/v1/runtime/callbacks status validation" do
    test "rejects missing status with 400", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/runtime/callbacks", %{})

      assert json_response(conn, 400)["error"] == "missing_status"
    end

    test "rejects unknown status with 400", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/runtime/callbacks", status: "vibes")

      assert json_response(conn, 400)["error"] == "invalid_status"
    end
  end

  describe "POST /cloud/v1/runtime/callbacks success paths" do
    test "transitions to in_progress and returns updated summary", %{
      conn: conn,
      token: token,
      package: package
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/runtime/callbacks", status: "in_progress")

      body = json_response(conn, 200)
      assert body["id"] == package.id
      assert body["status"] == "in_progress"
      assert body["runtime_target"] == "devin"
    end

    test "completed with result_summary and proof_refs is persisted", %{
      conn: conn,
      token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/runtime/callbacks",
          status: "completed",
          result_summary: "Implemented and tested",
          proof_refs: ["proof-1", "proof-2"]
        )

      body = json_response(conn, 200)
      assert body["status"] == "completed"
      assert body["result_summary"] == "Implemented and tested"
      assert body["proof_refs"] == "proof-1,proof-2"
      assert body["completed_at"]
    end

    test "failed with error_summary is persisted", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/runtime/callbacks",
          status: "failed",
          error_summary: "Hit unrecoverable error"
        )

      body = json_response(conn, 200)
      assert body["status"] == "failed"
      assert body["error_summary"] == "Hit unrecoverable error"
    end
  end

  describe "POST /cloud/v1/runtime/callbacks terminal protection" do
    test "rejects callbacks against terminal packages with 403", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/runtime/callbacks", status: "completed")

      assert json_response(conn, 200)["status"] == "completed"

      reposted =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/runtime/callbacks", status: "in_progress")

      body = json_response(reposted, 403)
      assert body["error"] == "package_is_terminal"
      assert body["status"] == "completed"
    end
  end
end
