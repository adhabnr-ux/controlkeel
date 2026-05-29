defmodule ControlKeelWeb.CloudUsageApiControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.{AuthToken, UsageMeter, WorkspaceIdentity, WorkspaceKeyRegistry}
  alias ControlKeel.Mission

  setup %{conn: conn} do
    UsageMeter.reset_all()

    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-usage-api-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(tmp_home)
    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      UsageMeter.reset_all()

      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    org = insert_org()
    workspace = insert_workspace(org)

    {:ok, identity, :created} = WorkspaceIdentity.ensure()
    {:ok, token} = AuthToken.sign(identity)
    {:ok, fingerprint} = WorkspaceKeyRegistry.fingerprint_for(identity.public_key)

    {:ok, _key} =
      WorkspaceKeyRegistry.enroll(%{
        workspace_id: identity.workspace_id,
        public_key: identity.public_key,
        algorithm: "ed25519",
        fingerprint: fingerprint,
        name: "usage-api-test",
        org_id: org.id,
        mission_workspace_id: workspace.id
      })

    conn = put_req_header(conn, "authorization", "Bearer #{token}")
    {:ok, conn: conn, org: org, workspace: workspace}
  end

  test "returns usage for authenticated workspace org", %{conn: conn, org: org} do
    :ok = UsageMeter.record(org.id, 125, emit: false)

    conn = get(conn, "/cloud/v1/orgs/#{org.slug}/usage")

    body = json_response(conn, 200)
    assert body["org_id"] == org.id
    assert body["org_slug"] == org.slug
    assert body["spend_cents"] == 125
  end

  test "rejects cross-org usage access", %{conn: conn} do
    other_org = insert_org()

    conn = get(conn, "/cloud/v1/orgs/#{other_org.slug}/usage")

    assert json_response(conn, 403)["error"] == "org_access_denied"
  end

  defp insert_org do
    s = "usage-org-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))

    {:ok, org} =
      %Accounts.Org{}
      |> Accounts.Org.changeset(%{name: s, slug: s, status: "active"})
      |> ControlKeel.Repo.insert()

    org
  end

  defp insert_workspace(org) do
    n = Integer.to_string(System.unique_integer([:positive, :monotonic]))

    {:ok, ws} =
      %Mission.Workspace{}
      |> Mission.Workspace.changeset(%{
        name: "Usage API #{n}",
        slug: "usage-api-#{n}",
        org_id: org.id,
        industry: "software",
        agent: "claude-code",
        budget_cents: 10_000,
        compliance_profile: "baseline",
        status: "active"
      })
      |> ControlKeel.Repo.insert()

    ws
  end
end
