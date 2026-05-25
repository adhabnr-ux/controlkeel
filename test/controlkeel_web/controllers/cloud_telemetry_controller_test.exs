defmodule ControlKeelWeb.CloudTelemetryControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Cloud.AuthToken
  alias ControlKeel.Cloud.Ingestion
  alias ControlKeel.Cloud.TelemetryConfig
  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Cloud.WorkspaceIdentity

  setup %{conn: conn} do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-telemetry-ctrl-test-#{System.unique_integer([:positive])}"
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
    {:ok, _state} = TelemetryConfig.enable(:governance)

    {:ok, envelope} = TelemetryEnvelope.build("finding.created", %{"severity" => "high"})

    conn = put_req_header(conn, "content-type", "application/json")

    {:ok, conn: conn, identity: identity, envelope: envelope}
  end

  describe "POST /cloud/v1/telemetry" do
    test "rejects missing Authorization header", %{
      conn: conn,
      identity: identity,
      envelope: envelope
    } do
      conn =
        post(conn, "/cloud/v1/telemetry",
          schema_version: "1",
          workspace_id: identity.workspace_id,
          events: [envelope]
        )

      assert json_response(conn, 401)["error"] == "missing_or_invalid_bearer"
    end

    test "rejects malformed Bearer header", %{conn: conn, identity: identity, envelope: envelope} do
      conn =
        conn
        |> put_req_header("authorization", "Basic abc")
        |> post("/cloud/v1/telemetry",
          schema_version: "1",
          workspace_id: identity.workspace_id,
          events: [envelope]
        )

      assert json_response(conn, 401)["error"] == "missing_or_invalid_bearer"
    end

    test "rejects a plain workspace_id Bearer (must be signed token)", %{
      conn: conn,
      identity: identity,
      envelope: envelope
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{identity.workspace_id}")
        |> post("/cloud/v1/telemetry",
          schema_version: "1",
          workspace_id: identity.workspace_id,
          events: [envelope]
        )

      assert json_response(conn, 401)["error"] == "invalid_token"
    end

    test "rejects an expired signed token", %{conn: conn, identity: identity, envelope: envelope} do
      {:ok, token} = AuthToken.sign(identity, ttl_seconds: -10)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/telemetry",
          schema_version: "1",
          workspace_id: identity.workspace_id,
          events: [envelope]
        )

      assert json_response(conn, 401)["error"] == "invalid_token"
    end

    test "rejects malformed batch with 400", %{conn: conn, identity: identity} do
      {:ok, token} = AuthToken.sign(identity)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/telemetry", %{})

      assert json_response(conn, 400)["error"] == "malformed_batch"
    end

    test "returns 403 when batch workspace_id differs from Bearer workspace_id", %{
      conn: conn,
      identity: identity,
      envelope: envelope
    } do
      {:ok, token} = AuthToken.sign(identity)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/telemetry",
          schema_version: "1",
          workspace_id: "ws_other",
          events: [envelope]
        )

      assert json_response(conn, 403)["error"] == "workspace_mismatch"
    end

    test "accepts a valid batch and returns per-envelope outcomes", %{
      conn: conn,
      identity: identity,
      envelope: envelope
    } do
      {:ok, token} = AuthToken.sign(identity)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/cloud/v1/telemetry",
          schema_version: "1",
          workspace_id: identity.workspace_id,
          events: [envelope]
        )

      body = json_response(conn, 202)
      assert body["accepted"] == 1
      assert body["duplicates"] == 0
      assert body["rejected"] == 0

      [outcome] = body["outcomes"]
      assert outcome["event_id"] == envelope["event_id"]
      assert outcome["status"] == "accepted"

      assert Ingestion.count() == 1
    end

    test "treats a second send of the same envelope as duplicate", %{
      conn: conn,
      identity: identity,
      envelope: envelope
    } do
      payload = %{
        schema_version: "1",
        workspace_id: identity.workspace_id,
        events: [envelope]
      }

      {:ok, token1} = AuthToken.sign(identity)
      {:ok, token2} = AuthToken.sign(identity)

      conn1 =
        conn
        |> put_req_header("authorization", "Bearer #{token1}")
        |> post("/cloud/v1/telemetry", payload)

      assert json_response(conn1, 202)["accepted"] == 1

      conn2 =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{token2}")
        |> post("/cloud/v1/telemetry", payload)

      body = json_response(conn2, 202)
      assert body["accepted"] == 0
      assert body["duplicates"] == 1
    end
  end
end
