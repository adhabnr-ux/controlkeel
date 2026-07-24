defmodule ControlKeel.AccountsTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.{Membership, Org}
  alias ControlKeel.Repo

  describe "create_user/1" do
    test "creates a user with normalized email" do
      assert {:ok, user} =
               Accounts.create_user(%{email: "  Alice@Example.COM  ", name: "Alice"})

      assert user.email == "alice@example.com"
      assert user.status == "active"
      assert user.id
    end

    test "rejects bad email shapes" do
      assert {:error, changeset} = Accounts.create_user(%{email: "not-an-email"})
      assert "has invalid format" in errors_on(changeset).email
    end

    test "enforces unique email" do
      {:ok, _} = Accounts.create_user(%{email: "dup@example.com"})
      assert {:error, changeset} = Accounts.create_user(%{email: "Dup@Example.com"})
      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "create_org/1" do
    test "creates an org with normalized slug" do
      assert {:ok, org} = Accounts.create_org(%{name: "Acme Inc", slug: "  ACME-INC "})
      assert org.slug == "acme-inc"
      assert org.status == "active"
    end

    test "rejects bad slugs" do
      assert {:error, changeset} = Accounts.create_org(%{name: "X", slug: "_bad start"})
      assert "has invalid format" in errors_on(changeset).slug
    end

    test "enforces unique slug" do
      {:ok, _} = Accounts.create_org(%{name: "One", slug: "shared-slug"})
      assert {:error, changeset} = Accounts.create_org(%{name: "Two", slug: "shared-slug"})
      assert "has already been taken" in errors_on(changeset).slug
    end
  end

  describe "create_org_with_owner/2" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "owner@example.com", name: "Owner"})
      {:ok, user: user}
    end

    test "creates an org and an active owner membership atomically", %{user: user} do
      assert {:ok, org} = Accounts.create_org_with_owner(user.id, %{name: "Acme", slug: "acme"})

      assert org.slug == "acme"
      assert org.status == "active"

      membership = Accounts.get_active_membership(user.id, org.id)
      assert membership != nil
      assert membership.role == "owner"
      assert membership.status == "active"
      assert membership.accepted_at != nil
      assert membership.invitation_token_hash == nil
    end

    test "rolls back both rows when the org insert fails", %{user: user} do
      {:ok, _} = Accounts.create_org(%{name: "Existing", slug: "taken"})

      assert {:error, changeset} =
               Accounts.create_org_with_owner(user.id, %{name: "Dup", slug: "taken"})

      assert "has already been taken" in errors_on(changeset).slug

      refute Repo.get_by(Org, slug: "taken") |> Map.get(:name) == "Dup"
      assert Repo.aggregate(Membership, :count) == 0
    end
  end

  describe "list_orgs_for_user/1" do
    test "returns only orgs where the user has an active membership, with role" do
      {:ok, user_a} = Accounts.create_user(%{email: "a@example.com"})
      {:ok, user_b} = Accounts.create_user(%{email: "b@example.com"})

      {:ok, org_a} = Accounts.create_org_with_owner(user_a.id, %{name: "Org A", slug: "org-a"})
      {:ok, _org_b} = Accounts.create_org_with_owner(user_b.id, %{name: "Org B", slug: "org-b"})

      # Unaffiliated org — should not appear for either user.
      {:ok, _} = Accounts.create_org(%{name: "Lonely", slug: "lonely"})

      [row_a] = Accounts.list_orgs_for_user(user_a.id)
      assert row_a.org.id == org_a.id
      assert row_a.role == "owner"
    end

    test "ignores pending memberships" do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})
      {:ok, invitee} = Accounts.create_user(%{email: "invitee@example.com"})
      {:ok, org} = Accounts.create_org_with_owner(owner.id, %{name: "Own", slug: "own"})

      {:ok, _membership, _token} =
        Accounts.invite_member(invitee.id, org.id, role: "member", invited_by_user_id: owner.id)

      # Invitee has only a pending membership — they should not see the org.
      assert Accounts.list_orgs_for_user(invitee.id) == []

      [row] = Accounts.list_orgs_for_user(owner.id)
      assert row.org.id == org.id
      assert row.role == "owner"
    end

    test "preserves distinct roles when a user holds different roles across orgs" do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})
      {:ok, other} = Accounts.create_user(%{email: "other@example.com"})

      {:ok, _owned} = Accounts.create_org_with_owner(owner.id, %{name: "Owned", slug: "owned"})
      {:ok, other_org} = Accounts.create_org_with_owner(other.id, %{name: "Other Org", slug: "other-org"})

      {:ok, _, token} =
        Accounts.invite_member(owner.id, other_org.id, role: "member", invited_by_user_id: other.id)

      {:ok, _} = Accounts.accept_invitation(token, owner.id)

      rows = Accounts.list_orgs_for_user(owner.id)
      role_by_slug = Map.new(rows, fn row -> {row.org.slug, row.role} end)

      assert role_by_slug["owned"] == "owner"
      assert role_by_slug["other-org"] == "member"
    end
  end

  describe "lookups" do
    setup do
      {:ok, user} = Accounts.create_user(%{email: "find@example.com", name: "Find"})
      {:ok, org} = Accounts.create_org(%{name: "Findable", slug: "findable"})
      {:ok, user: user, org: org}
    end

    test "get_user_by_email/1 is case insensitive", %{user: user} do
      assert Accounts.get_user_by_email("Find@Example.com").id == user.id
    end

    test "get_org_by_slug/1 is case insensitive", %{org: org} do
      assert Accounts.get_org_by_slug("FINDABLE").id == org.id
    end

    test "list filters by status" do
      {:ok, disabled} = Accounts.create_user(%{email: "x@example.com"})
      {:ok, _} = Accounts.disable_user(disabled.id)

      assert Enum.count(Accounts.list_users(status: "active")) == 1
      assert Enum.count(Accounts.list_users(status: "disabled")) == 1
    end
  end

  describe "invite_member/3 → accept_invitation/2" do
    setup do
      {:ok, owner} = Accounts.create_user(%{email: "owner@example.com"})
      {:ok, invitee} = Accounts.create_user(%{email: "invitee@example.com"})
      {:ok, org} = Accounts.create_org(%{name: "Team", slug: "team"})
      {:ok, owner: owner, invitee: invitee, org: org}
    end

    test "produces a one-time token; membership stores only its hash", %{
      invitee: invitee,
      org: org,
      owner: owner
    } do
      assert {:ok, membership, raw_token} =
               Accounts.invite_member(invitee.id, org.id,
                 role: "admin",
                 invited_by_user_id: owner.id
               )

      assert membership.status == "pending"
      assert membership.role == "admin"
      assert membership.invited_by_user_id == owner.id
      assert is_binary(raw_token)
      assert is_binary(membership.invitation_token_hash)
      refute membership.invitation_token_hash == raw_token
    end

    test "accepting flips status to active and clears the hash", %{invitee: invitee, org: org} do
      {:ok, _m, raw_token} = Accounts.invite_member(invitee.id, org.id)

      {:ok, accepted} = Accounts.accept_invitation(raw_token, invitee.id)

      assert accepted.status == "active"
      assert accepted.invitation_token_hash == nil
      assert %DateTime{} = accepted.accepted_at
    end

    test "rejects an invalid token", %{invitee: invitee} do
      assert {:error, :invalid_token} =
               Accounts.accept_invitation("nope-not-a-real-token", invitee.id)
    end

    test "rejects a token presented by the wrong user", %{
      invitee: invitee,
      owner: owner,
      org: org
    } do
      {:ok, _m, raw_token} = Accounts.invite_member(invitee.id, org.id)
      assert {:error, :invalid_token} = Accounts.accept_invitation(raw_token, owner.id)
    end

    test "rejects double-accept", %{invitee: invitee, org: org} do
      {:ok, _m, raw_token} = Accounts.invite_member(invitee.id, org.id)
      {:ok, _} = Accounts.accept_invitation(raw_token, invitee.id)

      assert {:error, :invalid_token} = Accounts.accept_invitation(raw_token, invitee.id)
    end

    test "prevents duplicate active membership for the same (user, org)", %{
      invitee: invitee,
      org: org
    } do
      {:ok, _m, _t} = Accounts.invite_member(invitee.id, org.id)
      assert {:error, :already_member} = Accounts.invite_member(invitee.id, org.id)
    end

    test "revives a revoked membership with a fresh token", %{
      invitee: invitee,
      org: org
    } do
      {:ok, _m, _t} = Accounts.invite_member(invitee.id, org.id, role: "member")
      {:ok, membership} = Accounts.revoke_membership(
        Accounts.list_memberships_for_org(org.id) |> hd() |> Map.get(:id)
      )
      assert membership.status == "revoked"

      {:ok, revived, new_token} = Accounts.invite_member(invitee.id, org.id, role: "admin")
      assert revived.status == "pending"
      assert revived.role == "admin"
      assert revived.accepted_at == nil
      assert is_binary(new_token)

      {:ok, accepted} = Accounts.accept_invitation(new_token, invitee.id)
      assert accepted.status == "active"
    end

    test "rejects unknown role" do
      {:ok, invitee} = Accounts.create_user(%{email: "u@example.com"})
      {:ok, org} = Accounts.create_org(%{name: "X", slug: "x"})

      assert {:error, changeset} = Accounts.invite_member(invitee.id, org.id, role: "god")
      assert "is invalid" in errors_on(changeset).role
    end
  end

  describe "list_memberships_for_org/2 and list_memberships_for_user/2" do
    test "scope by org and by user" do
      {:ok, alice} = Accounts.create_user(%{email: "alice@example.com"})
      {:ok, bob} = Accounts.create_user(%{email: "bob@example.com"})
      {:ok, org_a} = Accounts.create_org(%{name: "A", slug: "a"})
      {:ok, org_b} = Accounts.create_org(%{name: "B", slug: "b"})

      {:ok, _, _} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _, _} = Accounts.invite_member(alice.id, org_b.id)
      {:ok, _, _} = Accounts.invite_member(bob.id, org_a.id)

      assert length(Accounts.list_memberships_for_org(org_a.id)) == 2
      assert length(Accounts.list_memberships_for_user(alice.id)) == 2
      assert length(Accounts.list_memberships_for_user(bob.id)) == 1
    end
  end

  describe "workspace ↔ org linkage" do
    setup do
      {:ok, alice} = Accounts.create_user(%{email: "alice@example.com"})
      {:ok, bob} = Accounts.create_user(%{email: "bob@example.com"})
      {:ok, org_a} = Accounts.create_org(%{name: "Org A", slug: "org-a"})
      {:ok, org_b} = Accounts.create_org(%{name: "Org B", slug: "org-b"})

      ws_a = ControlKeel.MissionFixtures.workspace_fixture(%{name: "WS A", slug: "ws-a"})
      ws_b = ControlKeel.MissionFixtures.workspace_fixture(%{name: "WS B", slug: "ws-b"})

      ws_unaffiliated =
        ControlKeel.MissionFixtures.workspace_fixture(%{name: "WS Solo", slug: "ws-solo"})

      {:ok,
       alice: alice,
       bob: bob,
       org_a: org_a,
       org_b: org_b,
       ws_a: ws_a,
       ws_b: ws_b,
       ws_unaffiliated: ws_unaffiliated}
    end

    test "assign_workspace_to_org/2 links and unlinks", %{ws_a: ws, org_a: org} do
      assert {:ok, linked} = Accounts.assign_workspace_to_org(ws.id, org.id)
      assert linked.org_id == org.id

      assert {:ok, unlinked} = Accounts.assign_workspace_to_org(ws.id, nil)
      assert unlinked.org_id == nil
    end

    test "assign_workspace_to_org/2 returns :not_found for unknown workspace" do
      assert {:error, :not_found} = Accounts.assign_workspace_to_org(999_999, 1)
    end

    test "list_workspaces_for_org/1 returns only that org's workspaces", %{
      ws_a: ws_a,
      ws_b: ws_b,
      org_a: org_a,
      org_b: org_b
    } do
      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)
      {:ok, _} = Accounts.assign_workspace_to_org(ws_b.id, org_b.id)

      assert [%{id: id}] = Accounts.list_workspaces_for_org(org_a.id)
      assert id == ws_a.id
    end

    test "list_unaffiliated_workspaces/0 excludes linked workspaces", %{
      ws_a: ws_a,
      ws_unaffiliated: solo,
      org_a: org_a
    } do
      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)

      ids = Enum.map(Accounts.list_unaffiliated_workspaces(), & &1.id)
      assert solo.id in ids
      refute ws_a.id in ids
    end

    test "list_workspaces_for_user/1 follows active memberships", %{
      alice: alice,
      ws_a: ws_a,
      ws_b: ws_b,
      org_a: org_a,
      org_b: org_b
    } do
      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)
      {:ok, _} = Accounts.assign_workspace_to_org(ws_b.id, org_b.id)

      {:ok, m_a, raw_a} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _} = Accounts.accept_invitation(raw_a, alice.id)
      _ = m_a

      {:ok, _, _raw_b} = Accounts.invite_member(alice.id, org_b.id)

      ids = Enum.map(Accounts.list_workspaces_for_user(alice.id), & &1.id)

      assert ws_a.id in ids
      refute ws_b.id in ids
    end

    test "list_workspaces_for_user/1 ignores revoked memberships", %{
      alice: alice,
      ws_a: ws_a,
      org_a: org_a
    } do
      {:ok, _} = Accounts.assign_workspace_to_org(ws_a.id, org_a.id)
      {:ok, m, raw} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _} = Accounts.accept_invitation(raw, alice.id)
      {:ok, _} = Accounts.revoke_membership(m.id)

      assert Accounts.list_workspaces_for_user(alice.id) == []
    end

    test "list_workspaces_for_user/1 excludes unaffiliated workspaces", %{
      alice: alice,
      ws_unaffiliated: solo,
      org_a: org_a
    } do
      {:ok, _, raw} = Accounts.invite_member(alice.id, org_a.id)
      {:ok, _} = Accounts.accept_invitation(raw, alice.id)

      ids = Enum.map(Accounts.list_workspaces_for_user(alice.id), & &1.id)
      refute solo.id in ids
    end
  end

  describe "revoke_membership/1" do
    test "marks status as revoked" do
      {:ok, user} = Accounts.create_user(%{email: "u@example.com"})
      {:ok, org} = Accounts.create_org(%{name: "X", slug: "x"})
      {:ok, m, _t} = Accounts.invite_member(user.id, org.id)

      {:ok, revoked} = Accounts.revoke_membership(m.id)
      assert revoked.status == "revoked"
    end

    test "returns :not_found for unknown id" do
      assert {:error, :not_found} = Accounts.revoke_membership(999_999)
    end
  end
end
