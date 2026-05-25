defmodule ControlKeel.Cloud.Enrollment do
  @moduledoc """
  Build and verify proof-of-possession envelopes for workspace enrolment.

  The enrolment endpoint `POST /cloud/v1/workspaces/register` is intentionally
  unauthenticated at the HTTP layer — the caller has no prior credentials with
  the control plane. Trust comes from a signed envelope that proves the
  caller actually holds the private half of the public key they're submitting.

  ## Envelope shape

      {
        "workspace_id": "ws_...",
        "algorithm": "ed25519",
        "public_key": "<base64>",
        "name": "my-laptop",
        "invite_token": "<optional>",
        "proof": {
          "payload": "<base64url JSON>",
          "signature": "<base64url ed25519 signature>"
        }
      }

  The signed `payload` (before base64url-encoding) contains:

      {
        "workspace_id": "ws_...",
        "fingerprint": "<sha256 hex of public_key>",
        "algorithm": "ed25519",
        "issued_at": <unix seconds>
      }

  The server verifies the signature against the supplied `public_key`,
  rejects payloads whose `workspace_id` / `fingerprint` / `algorithm` do not
  match the envelope, and rejects timestamps drifting more than
  `@max_clock_skew_seconds` to limit replay.
  """

  @max_clock_skew_seconds 300
  @signature_size_bytes 64

  @type proof :: %{required(:payload) => String.t(), required(:signature) => String.t()}

  @typedoc "Verified enrolment fields."
  @type verified :: %{
          workspace_id: String.t(),
          algorithm: String.t(),
          public_key: String.t(),
          fingerprint: String.t(),
          name: String.t() | nil,
          invite_token: String.t() | nil
        }

  @type verify_error ::
          :malformed
          | :missing_fields
          | :unsupported_algorithm
          | :public_key_invalid
          | :proof_signature_invalid
          | :proof_payload_mismatch
          | :proof_expired
          | :proof_future_dated

  @doc """
  Build a proof-of-possession envelope ready to POST to `/cloud/v1/workspaces/register`.

  `identity` is the local `WorkspaceIdentity` struct. Optional `name` and
  `invite_token` are passed through unchanged.
  """
  @spec build(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(
        %{workspace_id: ws, public_key: pub_b64, private_key: priv_b64, fingerprint: fp} =
          _identity,
        opts \\ []
      ) do
    name = Keyword.get(opts, :name)
    invite_token = Keyword.get(opts, :invite_token)
    algorithm = "ed25519"
    issued_at = DateTime.utc_now() |> DateTime.to_unix()

    payload = %{
      "workspace_id" => ws,
      "fingerprint" => fp,
      "algorithm" => algorithm,
      "issued_at" => issued_at
    }

    payload_json = Jason.encode!(payload)

    with {:ok, priv} <- decode_b64(priv_b64),
         signature when is_binary(signature) <-
           :crypto.sign(:eddsa, :sha512, payload_json, [priv, :ed25519]) do
      envelope = %{
        "workspace_id" => ws,
        "algorithm" => algorithm,
        "public_key" => pub_b64,
        "name" => name,
        "invite_token" => invite_token,
        "proof" => %{
          "payload" => Base.url_encode64(payload_json, padding: false),
          "signature" => Base.url_encode64(signature, padding: false)
        }
      }

      {:ok, envelope}
    else
      :error -> {:error, :public_key_invalid}
      other -> {:error, other}
    end
  end

  @doc """
  Verify an enrolment envelope received from the network.

  Returns `{:ok, verified}` when the envelope is well-formed, the proof
  signature checks out against the supplied public key, and the payload
  agrees with the envelope's workspace_id/fingerprint/algorithm.
  """
  @spec verify(map()) :: {:ok, verified()} | {:error, verify_error()}
  def verify(envelope) when is_map(envelope) do
    with {:ok, fields} <- extract_envelope(envelope),
         {:ok, raw_pub} <- decode_b64(fields.public_key),
         expected_fp <- :crypto.hash(:sha256, raw_pub) |> Base.encode16(case: :lower),
         {:ok, payload_json, signature} <- decode_proof(fields.proof),
         {:ok, payload} <- decode_payload(payload_json),
         :ok <- check_payload_match(payload, fields, expected_fp),
         :ok <- check_clock(payload),
         :ok <- check_algorithm(fields.algorithm),
         :ok <- verify_signature(payload_json, signature, raw_pub) do
      {:ok,
       %{
         workspace_id: fields.workspace_id,
         algorithm: fields.algorithm,
         public_key: fields.public_key,
         fingerprint: expected_fp,
         name: fields.name,
         invite_token: fields.invite_token
       }}
    end
  end

  def verify(_), do: {:error, :malformed}

  defp extract_envelope(envelope) do
    required = ~w(workspace_id algorithm public_key proof)

    if Enum.all?(required, &Map.has_key?(envelope, &1)) do
      {:ok,
       %{
         workspace_id: Map.get(envelope, "workspace_id"),
         algorithm: Map.get(envelope, "algorithm"),
         public_key: Map.get(envelope, "public_key"),
         name: Map.get(envelope, "name"),
         invite_token: Map.get(envelope, "invite_token"),
         proof: Map.get(envelope, "proof")
       }}
    else
      {:error, :missing_fields}
    end
  end

  defp decode_proof(%{"payload" => p, "signature" => s}) when is_binary(p) and is_binary(s) do
    with {:ok, payload_json} <- url_decode(p),
         {:ok, sig} <- url_decode(s),
         true <- byte_size(sig) == @signature_size_bytes do
      {:ok, payload_json, sig}
    else
      _ -> {:error, :malformed}
    end
  end

  defp decode_proof(_), do: {:error, :malformed}

  defp decode_payload(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> {:error, :malformed}
    end
  end

  defp check_payload_match(payload, fields, expected_fp) do
    cond do
      Map.get(payload, "workspace_id") != fields.workspace_id ->
        {:error, :proof_payload_mismatch}

      Map.get(payload, "algorithm") != fields.algorithm ->
        {:error, :proof_payload_mismatch}

      Map.get(payload, "fingerprint") != expected_fp ->
        {:error, :proof_payload_mismatch}

      true ->
        :ok
    end
  end

  defp check_clock(%{"issued_at" => issued_at}) when is_integer(issued_at) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    drift = now - issued_at

    cond do
      drift > @max_clock_skew_seconds -> {:error, :proof_expired}
      drift < -@max_clock_skew_seconds -> {:error, :proof_future_dated}
      true -> :ok
    end
  end

  defp check_clock(_), do: {:error, :malformed}

  defp check_algorithm("ed25519"), do: :ok
  defp check_algorithm(_), do: {:error, :unsupported_algorithm}

  defp verify_signature(payload_json, signature, raw_pub) do
    if :crypto.verify(:eddsa, :sha512, payload_json, signature, [raw_pub, :ed25519]) do
      :ok
    else
      {:error, :proof_signature_invalid}
    end
  rescue
    _ -> {:error, :proof_signature_invalid}
  end

  defp decode_b64(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, :public_key_invalid}
    end
  end

  defp decode_b64(_), do: {:error, :public_key_invalid}

  defp url_decode(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :malformed}
    end
  end
end
