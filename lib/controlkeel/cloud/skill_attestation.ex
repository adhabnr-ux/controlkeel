defmodule ControlKeel.Cloud.SkillAttestation do
  @moduledoc """
  Verifies cryptographic attestation certificates attached to MCP skill entries.

  An attestation cert is a JSON envelope signed with an Ed25519 key:

      {
        "skill": "pii-scrubber",
        "url": "https://mcp.internal/pii",
        "issued_at": "2026-01-01T00:00:00Z",
        "expires_at": "2027-01-01T00:00:00Z",
        "issuer": "controlkeel-ca",
        "signature": "<base64url Ed25519 sig over canonical payload>"
      }

  The payload that is signed is the JSON object with `"signature"` removed,
  keys sorted, and serialized with no extra whitespace.

  Trusted public keys are configured under:

      config :controlkeel, :attestation_trusted_keys, [
        %{id: "controlkeel-ca", key: "<base64url Ed25519 pubkey>"}
      ]

  When no trusted keys are configured every cert verifies as `:unverified`
  rather than failing hard, allowing gradual rollout.
  """

  @type result :: :verified | :unverified | {:invalid, reason :: atom()}

  @doc """
  Verify a base64url-encoded attestation cert JSON string against trusted keys.

  Returns `:verified`, `:unverified` (no trusted keys configured or cert absent),
  or `{:invalid, reason}` if a cert is present but fails verification.
  """
  @spec verify(String.t() | nil, keyword()) :: result()
  def verify(nil, _opts), do: :unverified
  def verify("", _opts), do: :unverified

  def verify(cert_json, _opts) when is_binary(cert_json) do
    trusted_keys = Application.get_env(:controlkeel, :attestation_trusted_keys, [])

    if trusted_keys == [] do
      :unverified
    else
      case Jason.decode(cert_json) do
        {:ok, cert} -> do_verify(cert, trusted_keys)
        {:error, _} -> {:invalid, :bad_json}
      end
    end
  end

  @doc "Decode a cert JSON string into a map without verification."
  @spec decode(String.t() | nil) :: {:ok, map()} | {:error, atom()}
  def decode(nil), do: {:error, :missing}
  def decode(""), do: {:error, :missing}

  def decode(cert_json) do
    case Jason.decode(cert_json) do
      {:ok, map} -> {:ok, map}
      {:error, _} -> {:error, :bad_json}
    end
  end

  @doc "True iff `verify/2` returns `:verified`."
  @spec verified?(String.t() | nil, keyword()) :: boolean()
  def verified?(cert_json, opts \\ []) do
    verify(cert_json, opts) == :verified
  end

  # Private

  defp do_verify(cert, trusted_keys) do
    with {:ok, sig_b64} <- fetch_required(cert, "signature"),
         {:ok, issuer} <- fetch_required(cert, "issuer"),
         {:ok, pubkey_b64} <- find_key(trusted_keys, issuer),
         {:ok, sig} <- base64url_decode(sig_b64),
         {:ok, pubkey} <- base64url_decode(pubkey_b64),
         :ok <- check_expiry(cert),
         payload = canonical_payload(cert),
         true <- :crypto.verify(:eddsa, :none, payload, sig, [pubkey, :ed25519]) do
      :verified
    else
      {:error, reason} -> {:invalid, reason}
      false -> {:invalid, :bad_signature}
    end
  end

  defp fetch_required(map, key) do
    case Map.get(map, key) do
      nil -> {:error, String.to_atom("missing_#{key}")}
      val -> {:ok, val}
    end
  end

  defp find_key(trusted_keys, issuer) do
    case Enum.find(trusted_keys, fn k ->
           (Map.get(k, :id) || Map.get(k, "id")) == issuer
         end) do
      nil -> {:error, :unknown_issuer}
      k -> {:ok, Map.get(k, :key) || Map.get(k, "key")}
    end
  end

  defp base64url_decode(b64) do
    padded = pad_base64(b64)

    case Base.url_decode64(padded) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, :bad_base64}
    end
  end

  defp pad_base64(b64) do
    case rem(byte_size(b64), 4) do
      0 -> b64
      2 -> b64 <> "=="
      3 -> b64 <> "="
      _ -> b64
    end
  end

  defp check_expiry(cert) do
    case Map.get(cert, "expires_at") do
      nil ->
        :ok

      expires_str ->
        case DateTime.from_iso8601(expires_str) do
          {:ok, expires, _} ->
            if DateTime.compare(DateTime.utc_now(), expires) == :lt, do: :ok, else: {:error, :expired}

          _ ->
            {:error, :bad_expires_at}
        end
    end
  end

  defp canonical_payload(cert) do
    cert
    |> Map.delete("signature")
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.into(%{})
    |> Jason.encode!()
  end
end
