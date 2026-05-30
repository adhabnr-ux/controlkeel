defmodule ControlKeelWeb.InvitationLiveTest do
  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts

  setup do
    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})
    {:ok, invitee} = Accounts.create_user(%{email: "invitee@example.com"})
    {:ok, _m, raw_token} = Accounts.invite_member(invitee.id, org.id, role: "admin")

    {:ok, org: org, invitee: invitee, token: raw_token}
  end

  describe "GET /cloud/invitations/:token" do
    test "renders the join page for a valid pending invitation", %{
      conn: conn,
      org: org,
      invitee: invitee,
      token: token
    } do
      {:ok, _view, html} = live(conn, "/cloud/invitations/#{token}")

      assert html =~ "Join " <> org.name
      assert html =~ "admin"
      assert html =~ invitee.email
    end

    test "renders 'invitation not found' for an unknown token", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/cloud/invitations/not-a-real-token")
      assert html =~ "Invitation not found"
    end

    test "renders 'Invitation not found' after the token has been used", %{
      conn: conn,
      invitee: invitee,
      token: token
    } do
      # Acceptance clears the token hash, so the same raw token can no longer be
      # looked up — that's the correct security posture.
      {:ok, _} = Accounts.accept_invitation(token, invitee.id)

      {:ok, _view, html} = live(conn, "/cloud/invitations/#{token}")
      assert html =~ "Invitation not found"
    end
  end

  describe "accept event" do
    test "accepts the invitation when email matches", %{
      conn: conn,
      invitee: invitee,
      token: token
    } do
      {:ok, view, _html} = live(conn, "/cloud/invitations/#{token}")

      _html =
        view
        |> form("#invitation-accept-form", %{"email" => invitee.email})
        |> render_submit()

      [membership] = Accounts.list_memberships_for_user(invitee.id)
      assert membership.status == "active"
      assert membership.invitation_token_hash == nil
      assert %DateTime{} = membership.accepted_at
    end

    test "shows error when email does not match", %{conn: conn, token: token} do
      {:ok, view, _html} = live(conn, "/cloud/invitations/#{token}")

      html =
        view
        |> form("#invitation-accept-form", %{"email" => "someone-else@example.com"})
        |> render_submit()

      assert html =~ "does not match the invitation"
    end

    test "case-insensitive email match", %{conn: conn, invitee: invitee, token: token} do
      {:ok, view, _html} = live(conn, "/cloud/invitations/#{token}")

      _ =
        view
        |> form("#invitation-accept-form", %{"email" => String.upcase(invitee.email)})
        |> render_submit()

      [membership] = Accounts.list_memberships_for_user(invitee.id)
      assert membership.status == "active"
    end
  end
end
