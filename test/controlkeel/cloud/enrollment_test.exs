defmodule ControlKeel.Cloud.EnrollmentTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Cloud.Enrollment

  defp fresh_identity(_ \\ nil) do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    pub_b64 = Base.encode64(pub)
    priv_b64 = Base.encode64(priv)
    fp = :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)

    %{
      workspace_id:
        "ws_" <> Base.encode32(:crypto.strong_rand_bytes(8), padding: false, case: :lower),
      algorithm: "ed25519",
      public_key: pub_b64,
      private_key: priv_b64,
      fingerprint: fp
    }
  end

  describe "build/2 + verify/1 round-trip" do
    test "produces an envelope that verifies" do
      identity = fresh_identity()

      assert {:ok, envelope} = Enrollment.build(identity, name: "alpha", invite_token: "t-123")
      assert envelope["workspace_id"] == identity.workspace_id
      assert envelope["public_key"] == identity.public_key
      assert envelope["name"] == "alpha"
      assert envelope["invite_token"] == "t-123"

      assert {:ok, verified} = Enrollment.verify(envelope)
      assert verified.workspace_id == identity.workspace_id
      assert verified.fingerprint == identity.fingerprint
      assert verified.algorithm == "ed25519"
      assert verified.name == "alpha"
      assert verified.invite_token == "t-123"
    end

    test "envelope with nil name and invite_token still verifies" do
      identity = fresh_identity()

      {:ok, envelope} = Enrollment.build(identity)
      assert {:ok, verified} = Enrollment.verify(envelope)
      assert verified.name == nil
      assert verified.invite_token == nil
    end
  end

  describe "verify/1 trust checks" do
    test "rejects envelope where workspace_id differs from signed payload" do
      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity)

      tampered = Map.put(envelope, "workspace_id", "ws_attacker_forged")
      assert {:error, :proof_payload_mismatch} = Enrollment.verify(tampered)
    end

    test "rejects envelope where public_key was swapped for an attacker's key" do
      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity)

      {pub2, _} = :crypto.generate_key(:eddsa, :ed25519)
      tampered = Map.put(envelope, "public_key", Base.encode64(pub2))

      # The fingerprint computed by the server will not match the one in the
      # signed payload, so the mismatch surfaces first.
      assert {:error, :proof_payload_mismatch} = Enrollment.verify(tampered)
    end

    test "rejects envelope whose signature was forged with the wrong key" do
      identity_a = fresh_identity()
      identity_b = fresh_identity()

      # Build with B's private key but submit A's public key. The fingerprint
      # field in the signed payload will still match A's pubkey (because we
      # use A's fingerprint), but the signature will verify against B's pub.
      {:ok, envelope_b} = Enrollment.build(identity_b)

      tampered =
        envelope_b
        |> Map.put("workspace_id", identity_b.workspace_id)
        |> Map.put("public_key", identity_a.public_key)

      assert {:error, reason} = Enrollment.verify(tampered)
      assert reason in [:proof_signature_invalid, :proof_payload_mismatch]
    end

    test "rejects malformed envelope" do
      assert {:error, :missing_fields} = Enrollment.verify(%{"workspace_id" => "ws_x"})
      assert {:error, :malformed} = Enrollment.verify("not a map")
    end

    test "rejects envelope with unsupported algorithm" do
      identity = fresh_identity()
      {:ok, envelope} = Enrollment.build(identity)
      tampered = Map.put(envelope, "algorithm", "rsa-2048")

      assert {:error, reason} = Enrollment.verify(tampered)
      # Payload still says ed25519 → mismatch fires before algorithm gate.
      assert reason in [:unsupported_algorithm, :proof_payload_mismatch]
    end
  end
end
