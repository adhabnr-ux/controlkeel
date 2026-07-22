defmodule ControlKeelWeb.OidcControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts

  setup do
    original_adapter = Application.get_env(:controlkeel, :oidc_client_adapter)
    original_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)

    Application.put_env(:controlkeel, :oidc_client_adapter, ControlKeel.OidcTestAdapter)
    Application.put_env(:controlkeel, :runtime_mode, :cloud)

    on_exit(fn ->
      if original_adapter do
        Application.put_env(:controlkeel, :oidc_client_adapter, original_adapter)
      else
        Application.delete_env(:controlkeel, :oidc_client_adapter)
      end

      if is_nil(original_runtime_mode) do
        Application.delete_env(:controlkeel, :runtime_mode)
      else
        Application.put_env(:controlkeel, :runtime_mode, original_runtime_mode)
      end
    end)

    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})

    {:ok, _} =
      Accounts.set_org_identity_provider(org.id, %{
        type: "oidc",
        issuer: "https://login.example.com",
        client_id: "ck-cloud"
      })

    {:ok, org: org}
  end

  describe "GET /auth/oidc/start" do
    test "redirects to configured authorize endpoint and stores state", %{conn: conn} do
      conn = get(conn, "/auth/oidc/start?org=acme")

      assert redirected_to(conn, 302) =~ "https://login.example.com/authorize?"
      location = List.first(get_resp_header(conn, "location"))
      uri = URI.parse(location)
      params = URI.decode_query(uri.query)

      assert params["response_type"] == "code"
      assert params["client_id"] == "ck-cloud"
      assert params["scope"] == "openid email profile"
      assert params["redirect_uri"] =~ "/auth/oidc/callback"
      assert params["state"] == get_session(conn, :oidc_state)
      assert get_session(conn, :oidc_org_id)
    end

    test "returns 404 for unknown org", %{conn: conn} do
      conn = get(conn, "/auth/oidc/start?org=unknown")
      assert response(conn, 404) =~ "Org not found"
    end

    test "rejects orgs without OIDC config", %{conn: conn} do
      {:ok, org} = Accounts.create_org(%{name: "No SSO", slug: "no-sso"})
      assert Accounts.get_org_identity_provider(org.id) == nil

      conn = get(conn, "/auth/oidc/start?org=no-sso")
      assert response(conn, 400) =~ "OIDC is not configured"
    end

    test "rejects SAML-only orgs", %{conn: conn} do
      {:ok, org} = Accounts.create_org(%{name: "SAML", slug: "saml"})

      {:ok, _} =
        Accounts.set_org_identity_provider(org.id, %{
          type: "saml",
          entity_id: "https://ck.example/sso/saml",
          idp_metadata_url: "https://idp.example/metadata"
        })

      conn = get(conn, "/auth/oidc/start?org=saml")
      assert response(conn, 400) =~ "OIDC is not configured"
    end
  end

  describe "GET /auth/oidc/callback" do
    test "provisions user and active membership when state and claims are valid", %{
      conn: conn,
      org: org
    } do
      ControlKeel.OidcTestAdapter.put("provider-code", %{
        "email" => "CAROL@example.com",
        "name" => "Carol",
        "iss" => "https://login.example.com",
        "aud" => "ck-cloud",
        "exp" => System.system_time(:second) + 300
      })

      conn =
        conn
        |> init_test_session(%{oidc_state: "state-123", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{
          "state" => "state-123",
          "code" => "provider-code",
          "email" => "mallory@example.com",
          "name" => "Mallory"
        })

      assert redirected_to(conn, 302) == "/cloud/projects"
      user = Accounts.get_user_by_email("carol@example.com")
      assert get_session(conn, :current_user_id) == user.id
      assert get_session(conn, :current_org_id) == org.id
      refute get_session(conn, :oidc_state)
      refute get_session(conn, :oidc_org_id)
      assert user.name == "Carol"
      assert Accounts.get_user_by_email("mallory@example.com") == nil
      [membership] = Accounts.list_memberships_for_user(user.id, status: "active")
      assert membership.org_id == org.id
    end

    test "fails closed on state mismatch", %{conn: conn, org: org} do
      conn =
        conn
        |> init_test_session(%{oidc_state: "expected", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{
          "state" => "wrong",
          "code" => "provider-code",
          "email" => "mallory@example.com"
        })

      assert response(conn, 403) =~ "Invalid OIDC state"
      assert Accounts.get_user_by_email("mallory@example.com") == nil
    end

    test "requires provider code", %{conn: conn, org: org} do
      conn =
        conn
        |> init_test_session(%{oidc_state: "state", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{"state" => "state", "email" => "d@example.com"})

      assert response(conn, 400) =~ "Missing OIDC code"
    end

    test "requires email claim", %{conn: conn, org: org} do
      ControlKeel.OidcTestAdapter.put("code", {:error, :missing_email})

      conn =
        conn
        |> init_test_session(%{oidc_state: "state", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{"state" => "state", "code" => "code"})

      assert response(conn, 400) =~ "OIDC claims missing email"
    end

    test "surfaces issuer mismatch", %{conn: conn, org: org} do
      ControlKeel.OidcTestAdapter.put("bad-issuer", {:error, :issuer_mismatch})

      conn =
        conn
        |> init_test_session(%{oidc_state: "state", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{"state" => "state", "code" => "bad-issuer"})

      assert response(conn, 403) =~ "OIDC issuer mismatch"
    end

    test "surfaces audience mismatch", %{conn: conn, org: org} do
      ControlKeel.OidcTestAdapter.put("bad-aud", {:error, :audience_mismatch})

      conn =
        conn
        |> init_test_session(%{oidc_state: "state", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{"state" => "state", "code" => "bad-aud"})

      assert response(conn, 403) =~ "OIDC audience mismatch"
    end

    test "surfaces expired token", %{conn: conn, org: org} do
      ControlKeel.OidcTestAdapter.put("expired", {:error, :token_expired})

      conn =
        conn
        |> init_test_session(%{oidc_state: "state", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{"state" => "state", "code" => "expired"})

      assert response(conn, 403) =~ "OIDC token expired"
    end

    test "surfaces exchange failure", %{conn: conn, org: org} do
      ControlKeel.OidcTestAdapter.put("exchange-fails", {:error, {:token_exchange_failed, :boom}})

      conn =
        conn
        |> init_test_session(%{oidc_state: "state", oidc_org_id: org.id})
        |> get("/auth/oidc/callback", %{"state" => "state", "code" => "exchange-fails"})

      assert response(conn, 502) =~ "OIDC token exchange failed"
    end
  end
end
