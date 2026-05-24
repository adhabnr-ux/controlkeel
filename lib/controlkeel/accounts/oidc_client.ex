defmodule ControlKeel.Accounts.OidcClient do
  @moduledoc """
  OIDC token exchange and verification boundary.

  Controllers call this module instead of trusting callback request parameters as
  identity claims. In production the default adapter performs provider discovery
  and token exchange with `Req`, verifies RS256 ID-token signatures against
  provider JWKS, then validates issuer/audience/expiration/email claims. Tests
  and controlled deployments can inject an adapter with
  `config :controlkeel, :oidc_client_adapter, MyAdapter`.

  Client secrets are not stored in org settings. If needed, the default adapter
  reads them from runtime env using `CONTROLKEEL_OIDC_CLIENT_SECRET_<ORG_SLUG>`.
  """

  @callback exchange_and_verify(map(), String.t(), String.t(), keyword()) ::
              {:ok, map()} | {:error, atom() | term()}

  def exchange_and_verify(idp, code, redirect_uri, opts \\ []) do
    adapter().exchange_and_verify(idp, code, redirect_uri, opts)
  end

  defp adapter do
    Application.get_env(:controlkeel, :oidc_client_adapter, __MODULE__.DefaultAdapter)
  end

  defmodule DefaultAdapter do
    @behaviour ControlKeel.Accounts.OidcClient

    @impl true
    def exchange_and_verify(idp, code, redirect_uri, opts) when is_map(idp) and is_binary(code) do
      with {:ok, metadata} <- discover(idp, opts),
           {:ok, tokens} <- exchange_code(metadata, idp, code, redirect_uri, opts),
           {:ok, id_token} <- fetch_id_token(tokens),
           {:ok, claims} <- verify_id_token(id_token, idp, metadata, opts) do
        {:ok, claims}
      end
    end

    def exchange_and_verify(_, _, _, _), do: {:error, :invalid_oidc_request}

    defp discover(%{"issuer" => issuer}, opts) do
      discovery_url = String.trim_trailing(issuer, "/") <> "/.well-known/openid-configuration"

      case req_get(discovery_url, opts) do
        {:ok, %Req.Response{status: status, body: %{} = body}} when status in 200..299 ->
          {:ok, body}

        _ ->
          {:ok, %{"issuer" => issuer, "token_endpoint" => String.trim_trailing(issuer, "/") <> "/token"}}
      end
    end

    defp exchange_code(%{"token_endpoint" => endpoint}, idp, code, redirect_uri, opts) do
      form = %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => redirect_uri,
        "client_id" => idp["client_id"]
      }

      form =
        case client_secret(idp) do
          nil -> form
          secret -> Map.put(form, "client_secret", secret)
        end

      case req_post(endpoint, [form: form], opts) do
        {:ok, %Req.Response{status: status, body: %{} = body}} when status in 200..299 -> {:ok, body}
        {:ok, %Req.Response{status: status}} -> {:error, {:token_exchange_failed, status}}
        {:error, reason} -> {:error, {:token_exchange_failed, reason}}
      end
    end

    defp exchange_code(_, _, _, _, _), do: {:error, :missing_token_endpoint}

    defp fetch_id_token(%{"id_token" => token}) when is_binary(token) and token != "", do: {:ok, token}
    defp fetch_id_token(_), do: {:error, :missing_id_token}

    defp verify_id_token(id_token, idp, metadata, opts) do
      with {:ok, header, claims, signing_input, signature} <- decode_jwt(id_token),
           :ok <- verify_signature(header, signing_input, signature, metadata, opts),
           :ok <- verify_claims(claims, idp) do
        {:ok, claims}
      end
    end

    defp decode_jwt(id_token) do
      case String.split(id_token, ".") do
        [header64, payload64, signature64] ->
          with {:ok, header} <- decode_json_part(header64),
               {:ok, claims} <- decode_json_part(payload64),
               {:ok, signature} <- Base.url_decode64(signature64, padding: false) do
            {:ok, header, claims, header64 <> "." <> payload64, signature}
          else
            _ -> {:error, :invalid_id_token}
          end

        _ ->
          {:error, :invalid_id_token}
      end
    end

    defp decode_json_part(part) do
      with {:ok, json} <- Base.url_decode64(part, padding: false),
           {:ok, decoded} when is_map(decoded) <- Jason.decode(json) do
        {:ok, decoded}
      else
        _ -> {:error, :invalid_id_token}
      end
    end

    defp verify_signature(%{"alg" => "none"}, _input, _signature, _metadata, _opts),
      do: {:error, :unsupported_jwt_alg}

    defp verify_signature(%{"alg" => "RS256", "kid" => kid}, signing_input, signature, metadata, opts)
         when is_binary(kid) and kid != "" do
      with {:ok, jwks_uri} <- jwks_uri(metadata),
           {:ok, jwks} <- fetch_jwks(jwks_uri, opts),
           {:ok, jwk} <- select_jwk(jwks, kid),
           {:ok, public_key} <- rsa_public_key(jwk) do
        if :public_key.verify(signing_input, :sha256, signature, public_key) do
          :ok
        else
          {:error, :invalid_id_token_signature}
        end
      end
    end

    defp verify_signature(%{"alg" => "RS256"}, _input, _signature, _metadata, _opts),
      do: {:error, :missing_jwt_kid}

    defp verify_signature(_header, _input, _signature, _metadata, _opts),
      do: {:error, :unsupported_jwt_alg}

    defp jwks_uri(%{"jwks_uri" => uri}) when is_binary(uri) and uri != "", do: {:ok, uri}
    defp jwks_uri(_), do: {:error, :missing_jwks_uri}

    defp fetch_jwks(uri, opts) do
      case req_get(uri, opts) do
        {:ok, %Req.Response{status: status, body: %{"keys" => keys} = body}}
        when status in 200..299 and is_list(keys) ->
          {:ok, body}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:jwks_fetch_failed, status}}

        {:error, reason} ->
          {:error, {:jwks_fetch_failed, reason}}
      end
    end

    defp select_jwk(%{"keys" => keys}, kid) when is_list(keys) do
      case Enum.find(keys, &(Map.get(&1, "kid") == kid and Map.get(&1, "kty") == "RSA")) do
        nil -> {:error, :missing_jwks_key}
        jwk -> {:ok, jwk}
      end
    end

    defp select_jwk(_, _), do: {:error, :missing_jwks_key}

    defp rsa_public_key(%{"n" => n64, "e" => e64}) when is_binary(n64) and is_binary(e64) do
      with {:ok, n_bin} <- Base.url_decode64(n64, padding: false),
           {:ok, e_bin} <- Base.url_decode64(e64, padding: false) do
        {:ok, {:RSAPublicKey, :binary.decode_unsigned(n_bin), :binary.decode_unsigned(e_bin)}}
      else
        _ -> {:error, :invalid_jwk}
      end
    end

    defp rsa_public_key(_), do: {:error, :invalid_jwk}

    defp verify_claims(claims, idp) do
      cond do
        claims["iss"] != idp["issuer"] ->
          {:error, :issuer_mismatch}

        not audience_matches?(claims["aud"], idp["client_id"]) ->
          {:error, :audience_mismatch}

        expired?(claims["exp"]) ->
          {:error, :token_expired}

        !is_binary(claims["email"]) or String.trim(claims["email"]) == "" ->
          {:error, :missing_email}

        true ->
          :ok
      end
    end

    defp audience_matches?(aud, client_id) when is_binary(aud), do: aud == client_id
    defp audience_matches?(aud, client_id) when is_list(aud), do: client_id in aud
    defp audience_matches?(_, _), do: false

    defp expired?(exp) when is_integer(exp), do: exp <= System.system_time(:second)
    defp expired?(_), do: true

    defp client_secret(%{"client_secret_env" => env}) when is_binary(env), do: System.get_env(env)

    defp client_secret(%{"org_slug" => slug}) when is_binary(slug) do
      env = "CONTROLKEEL_OIDC_CLIENT_SECRET_" <> (slug |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "_"))
      System.get_env(env)
    end

    defp client_secret(_), do: nil

    defp req_get(url, opts), do: Keyword.get(opts, :http_client, Req).get(url)
    defp req_post(url, req_opts, opts), do: Keyword.get(opts, :http_client, Req).post(url, req_opts)
  end
end
