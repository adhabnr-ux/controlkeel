defmodule ControlKeel.CLI.AccountsAdminTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.CLI
  alias ControlKeel.MissionFixtures

  describe "user create" do
    test "creates a user and reports id/email" do
      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :user_create, options: %{email: "alice@example.com", name: "Alice"}, args: []},
                 File.cwd!()
               )

      assert Enum.any?(lines, &String.contains?(&1, "User created"))
      assert Enum.any?(lines, &String.contains?(&1, "alice@example.com"))
      assert Accounts.get_user_by_email("alice@example.com") != nil
    end

    test "missing --email errors with a helpful message" do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :user_create, options: %{}, args: []},
                 File.cwd!()
               )

      assert msg =~ "email"
    end

    test "invalid email surfaces changeset error" do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :user_create, options: %{email: "not-email"}, args: []},
                 File.cwd!()
               )

      assert msg =~ "Failed to create user"
    end
  end

  describe "org create / list" do
    test "creates an org" do
      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :org_create, options: %{name: "Acme", slug: "acme"}, args: []},
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Org created"))
      assert Accounts.get_org_by_slug("acme") != nil
    end

    test "list returns one row per org with budget summary" do
      {:ok, _} = Accounts.create_org(%{name: "Acme", slug: "acme"})
      {:ok, _} = Accounts.create_org(%{name: "Other", slug: "other"})

      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :org_list, options: %{}, args: []},
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "acme"))
      assert Enum.any?(lines, &(&1 =~ "other"))
      assert Enum.any?(lines, &(&1 =~ "uncapped"))
    end
  end

  describe "org budget set / show" do
    setup do
      {:ok, org} = Accounts.create_org(%{name: "Budget", slug: "budget"})
      {:ok, org: org}
    end

    test "sets a cap and shows it", %{org: org} do
      assert {:ok, _} =
               CLI.run_command(
                 %{command: :org_budget_set, options: %{cents: 5000}, args: [org.slug]},
                 File.cwd!()
               )

      assert Accounts.org_budget_cents(org.id) == 5000
    end

    test "--clear removes the cap", %{org: org} do
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 1234)

      assert {:ok, _} =
               CLI.run_command(
                 %{command: :org_budget_set, options: %{clear: true}, args: [org.slug]},
                 File.cwd!()
               )

      assert Accounts.org_budget_cents(org.id) == nil
    end

    test "show prints workspace breakdown when there is spend", %{org: org} do
      ws = MissionFixtures.workspace_fixture(%{slug: "ws-#{System.unique_integer([:positive])}"})
      {:ok, _} = Accounts.assign_workspace_to_org(ws.id, org.id)
      _ = MissionFixtures.session_fixture(%{workspace: ws, spent_cents: 250})
      {:ok, _} = Accounts.set_org_budget_cents(org.id, 1000)

      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :org_budget_show, options: %{}, args: [org.slug]},
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Spent: 250"))
      assert Enum.any?(lines, &(&1 =~ "Workspace breakdown"))
      assert Enum.any?(lines, &(&1 =~ ws.slug))
    end

    test "errors clearly when org slug is missing", %{} do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :org_budget_show, options: %{}, args: ["does-not-exist"]},
                 File.cwd!()
               )

      assert msg =~ "Org not found"
    end

    test "requires either --cents or --clear", %{org: org} do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :org_budget_set, options: %{}, args: [org.slug]},
                 File.cwd!()
               )

      assert msg =~ "--cents"
    end
  end

  describe "org invite / members" do
    setup do
      {:ok, org} = Accounts.create_org(%{name: "Team", slug: "team"})
      {:ok, org: org}
    end

    test "auto-creates a user when inviting an unknown email, returns raw token", %{org: org} do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :org_invite,
                   options: %{email: "new@example.com", role: "admin"},
                   args: [org.slug]
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Invitation created"))
      assert Enum.any?(lines, &(&1 =~ "Role: admin"))
      assert Enum.any?(lines, &String.contains?(&1, "Invitation token"))

      assert Accounts.get_user_by_email("new@example.com") != nil
    end

    test "rejects unknown org slug" do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :org_invite, options: %{email: "x@y.com"}, args: ["nope"]},
                 File.cwd!()
               )

      assert msg =~ "Org not found"
    end

    test "members lists invited users with role", %{org: org} do
      {:ok, _} =
        CLI.run_command(
          %{
            command: :org_invite,
            options: %{email: "carol@example.com", role: "member"},
            args: [org.slug]
          },
          File.cwd!()
        )

      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :org_members, options: %{}, args: [org.slug]},
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "carol@example.com"))
      assert Enum.any?(lines, &(&1 =~ "role=member"))
    end
  end
end
