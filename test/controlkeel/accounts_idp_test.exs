defmodule ControlKeel.AccountsIdpTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Accounts

  setup do
    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})
    {:ok, org: org}
  end

  describe "set_org_identity_provider/2 with OIDC" do
    test "accepts a valid OIDC config", %{org: org} do
      assert {:ok, _} =
               Accounts.set_org_identity_provider(org.id, %{
                 type: "oidc",
                 issuer: "https://login.example.com",
                 client_id: "ck-cloud"
               })

      assert %{"type" => "oidc", "issuer" => issuer, "client_id" => "ck-cloud"} =
               Accounts.get_org_identity_provider(org.id)

      assert issuer == "https://login.example.com"
    end

    test "rejects OIDC missing issuer", %{org: org} do
      assert {:error, {:missing_fields, fields}} =
               Accounts.set_org_identity_provider(org.id, %{
                 type: "oidc",
                 client_id: "ck-cloud"
               })

      assert "issuer" in fields
    end

    test "rejects OIDC missing client_id", %{org: org} do
      assert {:error, {:missing_fields, fields}} =
               Accounts.set_org_identity_provider(org.id, %{
                 type: "oidc",
                 issuer: "https://login.example.com"
               })

      assert "client_id" in fields
    end
  end

  describe "set_org_identity_provider/2 with SAML" do
    test "accepts a valid SAML config", %{org: org} do
      assert {:ok, _} =
               Accounts.set_org_identity_provider(org.id, %{
                 type: "saml",
                 entity_id: "https://controlkeel.example.com/sso/acme",
                 idp_metadata_url: "https://idp.example.com/metadata"
               })

      assert %{"type" => "saml"} = Accounts.get_org_identity_provider(org.id)
    end

    test "rejects SAML missing entity_id", %{org: org} do
      assert {:error, {:missing_fields, fields}} =
               Accounts.set_org_identity_provider(org.id, %{
                 type: "saml",
                 idp_metadata_url: "https://idp.example.com/metadata"
               })

      assert "entity_id" in fields
    end
  end

  describe "set_org_identity_provider/2 misc" do
    test "rejects an unknown provider type", %{org: org} do
      assert {:error, :unsupported_provider_type} =
               Accounts.set_org_identity_provider(org.id, %{type: "lol"})
    end

    test "rejects empty-string required fields as missing", %{org: org} do
      assert {:error, {:missing_fields, fields}} =
               Accounts.set_org_identity_provider(org.id, %{
                 type: "oidc",
                 issuer: "  ",
                 client_id: ""
               })

      assert "issuer" in fields
      assert "client_id" in fields
    end

    test "nil clears existing config and preserves other settings", %{org: org} do
      {:ok, _} =
        Accounts.set_org_identity_provider(org.id, %{
          type: "oidc",
          issuer: "https://i",
          client_id: "c"
        })

      {:ok, _} = Accounts.set_org_budget_cents(org.id, 999)
      {:ok, _} = Accounts.set_org_identity_provider(org.id, nil)

      assert Accounts.get_org_identity_provider(org.id) == nil
      assert Accounts.org_budget_cents(org.id) == 999
    end

    test "returns :not_found for unknown org" do
      assert {:error, :not_found} =
               Accounts.set_org_identity_provider(999_999, %{
                 type: "oidc",
                 issuer: "x",
                 client_id: "y"
               })
    end
  end

  describe "get_org_identity_provider/1" do
    test "returns nil when unset", %{org: org} do
      assert nil == Accounts.get_org_identity_provider(org.id)
    end

    test "returns nil for unknown org id" do
      assert nil == Accounts.get_org_identity_provider(999_999)
    end
  end
end
