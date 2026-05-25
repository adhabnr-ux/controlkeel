defmodule ControlKeel.Cloud.AuditExportSigner do
  @moduledoc """
  Deterministic digest and optional HMAC envelope for audit exports.

  Signing is intentionally stateless: callers provide signing material at runtime
  and the module never persists it. The payload is canonicalized by sorting map
  keys recursively before JSON encoding, so equivalent maps produce the same
  digest and signature.
  """

  @schema_version "1"
  @digest_alg "sha256"
  @signature_alg "hmac-sha256"

  @doc "Canonical JSON used for digest/signature operations."
  @spec canonical_json(term()) :: String.t()
  def canonical_json(value), do: value |> canonicalize() |> Jason.encode!()

  @doc "SHA256 digest of the canonical JSON payload, hex encoded."
  @spec digest(term()) :: String.t()
  def digest(payload) do
    :crypto.hash(:sha256, canonical_json(payload)) |> Base.encode16(case: :lower)
  end

  @doc "Wrap a payload in a signed envelope."
  @spec sign(term(), binary(), keyword()) :: map()
  def sign(payload, key, opts \\ []) when is_binary(key) and byte_size(key) > 0 do
    signed_at =
      Keyword.get_lazy(opts, :signed_at, fn ->
        DateTime.utc_now() |> DateTime.truncate(:second)
      end)

    key_id = Keyword.get(opts, :key_id, "env")
    canonical = canonical_json(payload)
    digest = :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
    signature = :crypto.mac(:hmac, :sha256, key, canonical) |> Base.encode16(case: :lower)

    %{
      "schema_version" => @schema_version,
      "kind" => "controlkeel.audit_export.signed",
      "signed_at" => DateTime.to_iso8601(signed_at),
      "payload" => payload,
      "integrity" => %{
        "digest_algorithm" => @digest_alg,
        "digest" => digest,
        "signature_algorithm" => @signature_alg,
        "signature" => signature,
        "key_id" => key_id
      }
    }
  end

  @doc "Verify a signed envelope against a runtime-provided key."
  @spec verify(map(), binary()) :: :ok | {:error, atom()}
  def verify(%{"payload" => payload, "integrity" => %{} = integrity}, key) when is_binary(key) do
    canonical = canonical_json(payload)
    expected_digest = :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
    expected_sig = :crypto.mac(:hmac, :sha256, key, canonical) |> Base.encode16(case: :lower)

    cond do
      integrity["digest_algorithm"] != @digest_alg ->
        {:error, :unsupported_digest_algorithm}

      integrity["signature_algorithm"] != @signature_alg ->
        {:error, :unsupported_signature_algorithm}

      integrity["digest"] != expected_digest ->
        {:error, :digest_mismatch}

      integrity["signature"] != expected_sig ->
        {:error, :signature_mismatch}

      true ->
        :ok
    end
  end

  def verify(_, _), do: {:error, :invalid_envelope}

  defp canonicalize(%{} = map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), canonicalize(v)} end)
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.into(%{})
  end

  defp canonicalize(list) when is_list(list), do: Enum.map(list, &canonicalize/1)
  defp canonicalize(value), do: value
end
