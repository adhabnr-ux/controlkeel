defmodule ControlKeel.Accounts.OidcClientTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Accounts.OidcClient.DefaultAdapter

  describe "default adapter JWKS verification" do
    test "accepts a valid RS256-signed ID token" do
      {private_key, jwk} = rsa_keypair("main-key")
      idp = %{"issuer" => "https://login.example.com", "client_id" => "ck-cloud"}

      token =
        signed_token(private_key, "main-key", %{
          "iss" => "https://login.example.com",
          "aud" => "ck-cloud",
          "exp" => future(),
          "email" => "alice@example.com",
          "name" => "Alice"
        })

      assert {:ok, claims} =
               DefaultAdapter.exchange_and_verify(idp, "code", "https://app/callback",
                 http_client: http_client(%{"id_token" => token}, [jwk])
               )

      assert claims["email"] == "alice@example.com"
      assert claims["name"] == "Alice"
    end

    test "rejects alg none tokens" do
      {_private_key, jwk} = rsa_keypair("main-key")

      token =
        unsigned_token(%{
          "iss" => "https://good",
          "aud" => "ck",
          "exp" => future(),
          "email" => "a@b.com"
        })

      assert {:error, :unsupported_jwt_alg} =
               DefaultAdapter.exchange_and_verify(
                 %{"issuer" => "https://good", "client_id" => "ck"},
                 "code",
                 "cb", http_client: http_client(%{"id_token" => token}, [jwk]))
    end

    test "rejects wrong key / invalid signature" do
      {private_key, _jwk} = rsa_keypair("main-key")
      {_wrong_private, wrong_jwk} = rsa_keypair("main-key")

      token =
        signed_token(private_key, "main-key", %{
          "iss" => "https://good",
          "aud" => "ck",
          "exp" => future(),
          "email" => "a@b.com"
        })

      assert {:error, :invalid_id_token_signature} =
               DefaultAdapter.exchange_and_verify(
                 %{"issuer" => "https://good", "client_id" => "ck"},
                 "code",
                 "cb", http_client: http_client(%{"id_token" => token}, [wrong_jwk]))
    end

    test "rejects missing JWKS key for kid" do
      {private_key, jwk} = rsa_keypair("different-key")

      token =
        signed_token(private_key, "main-key", %{
          "iss" => "https://good",
          "aud" => "ck",
          "exp" => future(),
          "email" => "a@b.com"
        })

      assert {:error, :missing_jwks_key} =
               DefaultAdapter.exchange_and_verify(
                 %{"issuer" => "https://good", "client_id" => "ck"},
                 "code",
                 "cb", http_client: http_client(%{"id_token" => token}, [jwk]))
    end

    test "rejects issuer mismatch after signature verification" do
      {private_key, jwk} = rsa_keypair("main-key")

      token =
        signed_token(private_key, "main-key", %{
          "iss" => "https://evil",
          "aud" => "ck",
          "exp" => future(),
          "email" => "a@b.com"
        })

      assert {:error, :issuer_mismatch} =
               DefaultAdapter.exchange_and_verify(
                 %{"issuer" => "https://good", "client_id" => "ck"},
                 "code",
                 "cb", http_client: http_client(%{"id_token" => token}, [jwk]))
    end

    test "rejects audience mismatch after signature verification" do
      {private_key, jwk} = rsa_keypair("main-key")

      token =
        signed_token(private_key, "main-key", %{
          "iss" => "https://good",
          "aud" => "other",
          "exp" => future(),
          "email" => "a@b.com"
        })

      assert {:error, :audience_mismatch} =
               DefaultAdapter.exchange_and_verify(
                 %{"issuer" => "https://good", "client_id" => "ck"},
                 "code",
                 "cb", http_client: http_client(%{"id_token" => token}, [jwk]))
    end

    test "rejects expired token after signature verification" do
      {private_key, jwk} = rsa_keypair("main-key")

      token =
        signed_token(private_key, "main-key", %{
          "iss" => "https://good",
          "aud" => "ck",
          "exp" => System.system_time(:second) - 1,
          "email" => "a@b.com"
        })

      assert {:error, :token_expired} =
               DefaultAdapter.exchange_and_verify(
                 %{"issuer" => "https://good", "client_id" => "ck"},
                 "code",
                 "cb", http_client: http_client(%{"id_token" => token}, [jwk]))
    end
  end

  defp future, do: System.system_time(:second) + 300

  defp rsa_keypair(kid) do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:RSAPrivateKey, _version, n, e, _d, _p1, _p2, _ex1, _ex2, _coeff, _other} = private_key

    jwk = %{
      "kty" => "RSA",
      "kid" => kid,
      "alg" => "RS256",
      "use" => "sig",
      "n" => n |> :binary.encode_unsigned() |> Base.url_encode64(padding: false),
      "e" => e |> :binary.encode_unsigned() |> Base.url_encode64(padding: false)
    }

    {private_key, jwk}
  end

  defp signed_token(private_key, kid, claims) do
    header =
      %{"alg" => "RS256", "kid" => kid} |> Jason.encode!() |> Base.url_encode64(padding: false)

    payload = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    signing_input = header <> "." <> payload

    signature =
      :public_key.sign(signing_input, :sha256, private_key) |> Base.url_encode64(padding: false)

    signing_input <> "." <> signature
  end

  defp unsigned_token(claims) do
    header = %{"alg" => "none"} |> Jason.encode!() |> Base.url_encode64(padding: false)
    payload = claims |> Jason.encode!() |> Base.url_encode64(padding: false)
    header <> "." <> payload <> "."
  end

  defp http_client(token_body, keys) do
    token_body = token_body
    jwks_body = %{"keys" => keys}

    discovery_body = %{
      "issuer" => "https://good",
      "token_endpoint" => "https://good/token",
      "jwks_uri" => "https://good/jwks"
    }

    module = Module.concat(__MODULE__, "Http#{System.unique_integer([:positive])}")

    {:module, ^module, _binary, _term} =
      Module.create(
        module,
        quote do
          def get(url) do
            cond do
              String.ends_with?(url, "/.well-known/openid-configuration") ->
                {:ok, %Req.Response{status: 200, body: unquote(Macro.escape(discovery_body))}}

              String.ends_with?(url, "/jwks") ->
                {:ok, %Req.Response{status: 200, body: unquote(Macro.escape(jwks_body))}}
            end
          end

          def post(_url, _opts),
            do: {:ok, %Req.Response{status: 200, body: unquote(Macro.escape(token_body))}}
        end,
        Macro.Env.location(__ENV__)
      )

    module
  end
end
