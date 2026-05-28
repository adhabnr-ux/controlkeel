defmodule ControlKeel.Cloud.WorkspaceKeyRegistryTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.WorkspaceKey
  alias ControlKeel.Cloud.WorkspaceKeyRegistry
  alias ControlKeel.Repo

  defp sample_key(attrs \\ %{}) do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
    pub_b64 = Base.encode64(pub)
    fp = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)

    Map.merge(
      %{
        workspace_id:
          "ws_" <> Base.encode32(:crypto.strong_rand_bytes(8), padding: false, case: :lower),
        public_key: pub_b64,
        algorithm: "ed25519",
        fingerprint: fp,
        name: "test-workspace",
        org_id: nil
      },
      attrs
    )
  end

  describe "enroll/1" do
    test "inserts a new registration" do
      attrs = sample_key()

      assert {:ok, %WorkspaceKey{} = key} = WorkspaceKeyRegistry.enroll(attrs)
      assert key.workspace_id == attrs.workspace_id
      assert key.fingerprint == attrs.fingerprint
      assert key.algorithm == "ed25519"
      assert key.revoked_at == nil
      assert %DateTime{} = key.last_seen_at
    end

    test "is idempotent on workspace_id and clears revoked_at" do
      attrs = sample_key()
      {:ok, first} = WorkspaceKeyRegistry.enroll(attrs)
      {:ok, _} = WorkspaceKeyRegistry.revoke(first.workspace_id)

      {:ok, second} = WorkspaceKeyRegistry.enroll(attrs)
      assert second.id == first.id
      assert second.revoked_at == nil
    end

    test "rejects malformed workspace_id" do
      attrs = sample_key(%{workspace_id: "not-a-ws-id"})

      assert {:error, %Ecto.Changeset{}} = WorkspaceKeyRegistry.enroll(attrs)
    end
  end

  describe "fetch/1" do
    test "returns active registration" do
      attrs = sample_key()
      {:ok, _} = WorkspaceKeyRegistry.enroll(attrs)

      assert {:ok, %WorkspaceKey{workspace_id: ws}} =
               WorkspaceKeyRegistry.fetch(attrs.workspace_id)

      assert ws == attrs.workspace_id
    end

    test "skips revoked rows" do
      attrs = sample_key()
      {:ok, _} = WorkspaceKeyRegistry.enroll(attrs)
      {:ok, _} = WorkspaceKeyRegistry.revoke(attrs.workspace_id)

      assert {:error, :not_found} = WorkspaceKeyRegistry.fetch(attrs.workspace_id)
    end

    test "returns :not_found for unknown workspace" do
      assert {:error, :not_found} = WorkspaceKeyRegistry.fetch("ws_nonexistent")
    end
  end

  describe "list_for_org/1" do
    test "returns only active keys bound to the given org" do
      org_a = insert_org()
      org_b = insert_org()

      {:ok, _} = WorkspaceKeyRegistry.enroll(sample_key(%{org_id: org_a.id}))
      {:ok, _} = WorkspaceKeyRegistry.enroll(sample_key(%{org_id: org_a.id}))
      {:ok, _} = WorkspaceKeyRegistry.enroll(sample_key(%{org_id: org_b.id}))
      {:ok, unbound} = WorkspaceKeyRegistry.enroll(sample_key())
      {:ok, _} = WorkspaceKeyRegistry.revoke(unbound.workspace_id)

      keys = WorkspaceKeyRegistry.list_for_org(org_a.id)
      assert length(keys) == 2
      assert Enum.all?(keys, &(&1.org_id == org_a.id))
    end

    test "nil org returns empty" do
      assert WorkspaceKeyRegistry.list_for_org(nil) == []
    end
  end

  describe "touch_last_seen/1" do
    test "updates last_seen_at on an existing key" do
      attrs = sample_key()
      {:ok, %WorkspaceKey{last_seen_at: before}} = WorkspaceKeyRegistry.enroll(attrs)

      Process.sleep(1100)
      assert :ok = WorkspaceKeyRegistry.touch_last_seen(attrs.workspace_id)

      {:ok, after_key} = WorkspaceKeyRegistry.fetch(attrs.workspace_id)
      assert DateTime.compare(after_key.last_seen_at, before) == :gt
    end

    test "is a no-op for unknown workspace" do
      assert :ok = WorkspaceKeyRegistry.touch_last_seen("ws_missing")
    end
  end

  describe "fingerprint_for/1" do
    test "matches hash of decoded public key" do
      {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
      pub_b64 = Base.encode64(pub)
      expected = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)

      assert {:ok, ^expected} = WorkspaceKeyRegistry.fingerprint_for(pub_b64)
    end

    test "rejects invalid base64" do
      assert {:error, :public_key_invalid} = WorkspaceKeyRegistry.fingerprint_for("not!base!64")
    end
  end

  defp insert_org do
    slug = "org-" <> Integer.to_string(System.unique_integer([:positive]))

    {:ok, org} =
      %ControlKeel.Accounts.Org{}
      |> ControlKeel.Accounts.Org.changeset(%{name: slug, slug: slug, status: "active"})
      |> Repo.insert()

    org
  end

  describe "enroll/1 with mission_workspace_id" do
    test "persists the mission workspace link" do
      org = insert_org()
      ws = insert_workspace(org)

      {:ok, key} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org.id,
          mission_workspace_id: ws.id
        }))

      assert key.mission_workspace_id == ws.id
    end

    test "preloaded mission_workspace returns the workspace struct" do
      org = insert_org()
      ws = insert_workspace(org)

      {:ok, key} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org.id,
          mission_workspace_id: ws.id
        }))

      loaded = Repo.preload(key, :mission_workspace)
      assert loaded.mission_workspace.slug == ws.slug
    end

    test "duplicate mission_workspace_id under same org is rejected" do
      org = insert_org()
      ws = insert_workspace(org)

      {:ok, _first} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org.id,
          mission_workspace_id: ws.id
        }))

      assert {:error, %Ecto.Changeset{}} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org.id,
          mission_workspace_id: ws.id
        }))
    end

    test "same mission_workspace_id under different orgs is allowed" do
      org_a = insert_org()
      org_b = insert_org()
      ws = insert_workspace(org_a)

      {:ok, _a} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org_a.id,
          mission_workspace_id: ws.id
        }))

      # Second enrollment under different org should succeed because
      # the unique index is scoped to (org_id, mission_workspace_id).
      {:ok, b} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org_b.id,
          mission_workspace_id: ws.id
        }))

      assert b.org_id == org_b.id
    end

    test "mission_workspace_id can be nil" do
      {:ok, key} = WorkspaceKeyRegistry.enroll(sample_key(%{mission_workspace_id: nil}))
      assert key.mission_workspace_id == nil
    end
  end

  describe "fetch_by_mission_workspace/1" do
    test "returns active key for the given mission workspace" do
      org = insert_org()
      ws = insert_workspace(org)

      {:ok, enrolled} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org.id,
          mission_workspace_id: ws.id
        }))

      assert {:ok, key} = WorkspaceKeyRegistry.fetch_by_mission_workspace(ws.id)
      assert key.workspace_id == enrolled.workspace_id
    end

    test "returns :not_found when no enrollment exists" do
      assert {:error, :not_found} = WorkspaceKeyRegistry.fetch_by_mission_workspace(999_999)
    end

    test "returns :not_found for revoked enrollment" do
      org = insert_org()
      ws = insert_workspace(org)

      {:ok, enrolled} =
        WorkspaceKeyRegistry.enroll(sample_key(%{
          org_id: org.id,
          mission_workspace_id: ws.id
        }))

      {:ok, _} = WorkspaceKeyRegistry.revoke(enrolled.workspace_id)

      assert {:error, :not_found} = WorkspaceKeyRegistry.fetch_by_mission_workspace(ws.id)
    end
  end

  defp insert_workspace(org) do
    n = Integer.to_string(System.unique_integer([:positive]))
    slug = "ws-#{n}"

    {:ok, ws} =
      %ControlKeel.Mission.Workspace{}
      |> ControlKeel.Mission.Workspace.changeset(%{
        name: "Test Workspace #{n}",
        slug: slug,
        org_id: org.id,
        industry: "technology",
        agent: "claude",
        budget_cents: 0,
        compliance_profile: "baseline",
        status: "active"
      })
      |> Repo.insert()

    ws
  end
end
