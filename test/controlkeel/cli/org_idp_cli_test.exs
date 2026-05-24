defmodule ControlKeel.CLI.OrgIdpTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.CLI

  setup do
    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})
    {:ok, org: org}
  end

  describe "org idp set" do
    test "configures OIDC", %{org: org} do
      assert {:ok, lines} =
               CLI.run_command(
                 %{
                   command: :org_idp_set,
                   options: %{
                     type: "oidc",
                     issuer: "https://login.example.com",
                     client_id: "ck-cloud"
                   },
                   args: [org.slug]
                 },
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Identity provider configured"))
      assert Accounts.get_org_identity_provider(org.id)["type"] == "oidc"
    end

    test "configures SAML", %{org: org} do
      assert {:ok, _} =
               CLI.run_command(
                 %{
                   command: :org_idp_set,
                   options: %{
                     type: "saml",
                     entity_id: "https://ck.example/sso/acme",
                     idp_metadata_url: "https://idp.example/metadata"
                   },
                   args: [org.slug]
                 },
                 File.cwd!()
               )

      assert Accounts.get_org_identity_provider(org.id)["type"] == "saml"
    end

    test "--clear removes the config", %{org: org} do
      {:ok, _} =
        Accounts.set_org_identity_provider(org.id, %{
          type: "oidc",
          issuer: "x",
          client_id: "y"
        })

      assert {:ok, _} =
               CLI.run_command(
                 %{command: :org_idp_set, options: %{clear: true}, args: [org.slug]},
                 File.cwd!()
               )

      assert Accounts.get_org_identity_provider(org.id) == nil
    end

    test "missing required fields surface a clear message", %{org: org} do
      assert {:error, msg} =
               CLI.run_command(
                 %{
                   command: :org_idp_set,
                   options: %{type: "oidc"},
                   args: [org.slug]
                 },
                 File.cwd!()
               )

      assert msg =~ "issuer"
    end

    test "unknown type produces a hint", %{org: org} do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :org_idp_set, options: %{type: "foo"}, args: [org.slug]},
                 File.cwd!()
               )

      assert msg =~ "oidc"
      assert msg =~ "saml"
    end

    test "unknown org slug errors", %{} do
      assert {:error, msg} =
               CLI.run_command(
                 %{command: :org_idp_set, options: %{type: "oidc"}, args: ["nope"]},
                 File.cwd!()
               )

      assert msg =~ "Org not found"
    end
  end

  describe "org idp show" do
    test "prints '(none)' when unconfigured", %{org: org} do
      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :org_idp_show, options: %{}, args: [org.slug]},
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "(none)"))
    end

    test "shows configured fields sorted", %{org: org} do
      {:ok, _} =
        Accounts.set_org_identity_provider(org.id, %{
          type: "oidc",
          issuer: "https://login.example.com",
          client_id: "ck-cloud"
        })

      assert {:ok, lines} =
               CLI.run_command(
                 %{command: :org_idp_show, options: %{}, args: [org.slug]},
                 File.cwd!()
               )

      assert Enum.any?(lines, &(&1 =~ "Type: oidc"))
      assert Enum.any?(lines, &(&1 =~ "client_id: ck-cloud"))
      assert Enum.any?(lines, &(&1 =~ "issuer: https://login.example.com"))
    end
  end
end
