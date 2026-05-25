defmodule ControlKeelWeb.SamlControllerTest do
  use ControlKeelWeb.ConnCase, async: false

  alias ControlKeel.Accounts
  alias ControlKeel.SamlTestAdapter

  setup do
    previous = Application.get_env(:controlkeel, :saml_client_adapter)
    Application.put_env(:controlkeel, :saml_client_adapter, SamlTestAdapter)

    on_exit(fn ->
      if previous do
        Application.put_env(:controlkeel, :saml_client_adapter, previous)
      else
        Application.delete_env(:controlkeel, :saml_client_adapter)
      end
    end)

    {:ok, org} = Accounts.create_org(%{name: "Acme", slug: "acme"})

    {:ok, _} =
      Accounts.set_org_identity_provider(org.id, %{
        type: "saml",
        entity_id: "https://ck.example/sso/acme",
        idp_metadata_url: "https://idp.example/metadata"
      })

    {:ok, org: org}
  end

  describe "GET /auth/saml/start" do
    test "redirects to the IdP SSO URL with RelayState and stores state in session", %{
      conn: conn,
      org: org
    } do
      SamlTestAdapter.put_sso_url("https://idp.example/sso")

      conn = get(conn, "/auth/saml/start", org: org.slug)

      location = redirected_to(conn, 302)
      assert location =~ "https://idp.example/sso"
      assert location =~ "RelayState="
      assert get_session(conn, :saml_org_id) == org.id
      assert is_binary(get_session(conn, :saml_relay_state))
    end

    test "returns 404 for unknown org slug", %{conn: conn} do
      conn = get(conn, "/auth/saml/start", org: "nope")
      assert response(conn, 404) =~ "Org not found"
    end

    test "returns 400 when org has no SAML config", %{conn: conn} do
      {:ok, plain_org} = Accounts.create_org(%{name: "Plain", slug: "plain"})

      conn = get(conn, "/auth/saml/start", org: plain_org.slug)
      assert response(conn, 400) =~ "SAML is not configured"
    end

    test "returns 503 when the adapter has no SSO URL stubbed", %{conn: conn, org: org} do
      conn = get(conn, "/auth/saml/start", org: org.slug)
      # No stub set → DefaultAdapter would also return :saml_adapter_not_configured;
      # the test adapter returns :sso_url_not_stubbed which surfaces as 400.
      assert response(conn, 400) =~ "SAML start failed"
    end
  end

  describe "POST /auth/saml/acs" do
    setup %{conn: conn, org: org} do
      SamlTestAdapter.put_sso_url("https://idp.example/sso")
      start_conn = get(conn, "/auth/saml/start", org: org.slug)
      relay_state = get_session(start_conn, :saml_relay_state)

      # Forward the session into a new conn for the ACS POST.
      conn =
        Phoenix.ConnTest.recycle(start_conn)
        |> put_req_header("content-type", "application/x-www-form-urlencoded")

      {:ok, conn: conn, relay_state: relay_state}
    end

    test "accepts a valid SAML response and signs the user in", %{
      conn: conn,
      relay_state: relay_state,
      org: org
    } do
      SamlTestAdapter.put_response("valid-response", %{
        "email" => "alice@example.com",
        "name" => "Alice"
      })

      conn =
        post(conn, "/auth/saml/acs", %{
          "SAMLResponse" => "valid-response",
          "RelayState" => relay_state
        })

      assert redirected_to(conn, 302) == "/cloud/telemetry"
      user = Accounts.get_user_by_email("alice@example.com")
      assert user
      assert get_session(conn, :current_user_id) == user.id
      assert get_session(conn, :current_org_id) == org.id
      refute get_session(conn, :saml_relay_state)
      refute get_session(conn, :saml_org_id)
    end

    test "rejects mismatched RelayState with 403", %{conn: conn} do
      conn =
        post(conn, "/auth/saml/acs", %{
          "SAMLResponse" => "valid-response",
          "RelayState" => "definitely-not-the-session-value"
        })

      assert response(conn, 403) =~ "Invalid SAML RelayState"
    end

    test "rejects missing SAMLResponse with 400", %{conn: conn, relay_state: relay_state} do
      conn = post(conn, "/auth/saml/acs", %{"RelayState" => relay_state})
      assert response(conn, 400) =~ "Missing SAMLResponse"
    end

    test "surfaces adapter signature errors as 403", %{conn: conn, relay_state: relay_state} do
      SamlTestAdapter.put_response("forged-response", {:error, :signature_invalid})

      conn =
        post(conn, "/auth/saml/acs", %{
          "SAMLResponse" => "forged-response",
          "RelayState" => relay_state
        })

      assert response(conn, 403) =~ "SAML signature invalid"
    end

    test "rejects claims missing email with 400", %{conn: conn, relay_state: relay_state} do
      SamlTestAdapter.put_response("no-email-response", %{"name" => "Anonymous"})

      conn =
        post(conn, "/auth/saml/acs", %{
          "SAMLResponse" => "no-email-response",
          "RelayState" => relay_state
        })

      assert response(conn, 400) =~ "missing email"
    end
  end

  describe "default adapter when no test adapter is installed" do
    test "start returns 503 with helpful message", %{conn: conn, org: org} do
      Application.delete_env(:controlkeel, :saml_client_adapter)

      conn = get(conn, "/auth/saml/start", org: org.slug)
      assert response(conn, 503) =~ "SAML adapter is not configured"
    end
  end
end
