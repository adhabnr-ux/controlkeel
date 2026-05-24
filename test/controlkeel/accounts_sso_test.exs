defmodule ControlKeel.AccountsSsoTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts

  setup do
    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})
    {:ok, org: org}
  end

  describe "ensure_sso_membership/3" do
    test "creates a user and active membership from trusted claims", %{org: org} do
      assert {:ok, user, membership} =
               Accounts.ensure_sso_membership(org.id, %{
                 "email" => "ALICE@example.com",
                 "name" => "Alice"
               })

      assert user.email == "alice@example.com"
      assert user.name == "Alice"
      assert membership.org_id == org.id
      assert membership.user_id == user.id
      assert membership.status == "active"
      assert membership.role == "member"
      assert membership.invitation_token_hash == nil
    end

    test "reuses an existing user and reactivates pending membership", %{org: org} do
      {:ok, user} = Accounts.create_user(%{email: "bob@example.com", name: "Bob"})
      {:ok, pending, _token} = Accounts.invite_member(user.id, org.id, role: "admin")

      assert {:ok, ^user, membership} =
               Accounts.ensure_sso_membership(org.id, %{"email" => "bob@example.com"})

      assert membership.id == pending.id
      assert membership.status == "active"
      assert membership.role == "admin"
      assert membership.invitation_token_hash == nil
    end

    test "returns :missing_email when claims do not contain email", %{org: org} do
      assert {:error, :missing_email} = Accounts.ensure_sso_membership(org.id, %{"name" => "No Email"})
    end

    test "returns :not_found for unknown org" do
      assert {:error, :not_found} =
               Accounts.ensure_sso_membership(999_999, %{"email" => "nobody@example.com"})
    end
  end
end
