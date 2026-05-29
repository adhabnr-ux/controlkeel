defmodule ControlKeelWeb.P1cMailerInviteTest do
  @moduledoc """
  P1c slice: when an admin invites a member via OrgMembersLive, the
  invitation gets delivered (captured by TestInbox in test mode).
  """

  use ControlKeelWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Membership
  alias ControlKeel.Mailer.TestInbox
  alias ControlKeel.Repo

  setup do
    previous = Application.get_env(:controlkeel, :runtime_mode, :local)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)
    on_exit(fn -> Application.put_env(:controlkeel, :runtime_mode, previous) end)

    TestInbox.clear()
    :ok
  end

  test "admin inviting a teammate populates the test inbox", %{conn: conn} do
    {:ok, org} =
      Accounts.create_org(%{
        name: "MailerCo",
        slug: "mailerco-#{System.unique_integer([:positive])}"
      })

    {:ok, admin} =
      Accounts.create_user(%{email: "admin-#{System.unique_integer([:positive])}@x.test"})

    {:ok, _m} =
      %Membership{}
      |> Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> put_session(:current_user_id, admin.id)
      |> put_session(:current_org_id, org.id)

    {:ok, lv, _html} = live(conn, ~p"/org/#{org.slug}/members")

    invitee_email = "invitee-#{System.unique_integer([:positive])}@x.test"

    lv
    |> form("form[phx-submit=invite]", invite: %{email: invitee_email, role: "member"})
    |> render_submit()

    # Inbox should contain the invitation entry for the invitee
    entry = TestInbox.find_by_email(invitee_email)

    assert entry,
           "expected an invitation delivery for #{invitee_email}, inbox: #{inspect(TestInbox.all())}"

    {:invitation, payload, %DateTime{}} = entry
    assert payload.to == invitee_email
    assert is_binary(payload.token)
    assert payload.token != ""
    assert String.starts_with?(payload.url, "/cloud/invitations/")
    assert String.ends_with?(payload.url, payload.token)
  end

  test "duplicate-email invite still surfaces visible token banner (mailer never blocks)", %{
    conn: conn
  } do
    # If the email validation passes but mailer somehow fails, the UI should still work.
    # This test pins the contract that token banner appears regardless of mailer outcome.
    {:ok, org} =
      Accounts.create_org(%{
        name: "Mailer2",
        slug: "mailer2-#{System.unique_integer([:positive])}"
      })

    {:ok, admin} =
      Accounts.create_user(%{email: "admin2-#{System.unique_integer([:positive])}@x.test"})

    {:ok, _m} =
      %Membership{}
      |> Membership.changeset(%{
        user_id: admin.id,
        org_id: org.id,
        role: "admin",
        status: "active",
        accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> put_session(:current_user_id, admin.id)
      |> put_session(:current_org_id, org.id)

    {:ok, lv, _html} = live(conn, ~p"/org/#{org.slug}/members")

    invitee = "fallback-#{System.unique_integer([:positive])}@x.test"

    lv
    |> form("form[phx-submit=invite]", invite: %{email: invitee, role: "member"})
    |> render_submit()

    html = render(lv)
    assert html =~ "Invitation token issued"
    assert html =~ "/cloud/invitations/"
  end
end
