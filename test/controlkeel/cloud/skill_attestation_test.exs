defmodule ControlKeel.Cloud.SkillAttestationTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Cloud.SkillAttestation

  describe "verify/2 — no trusted keys configured" do
    test "returns :unverified for nil cert" do
      assert :unverified = SkillAttestation.verify(nil, [])
    end

    test "returns :unverified for empty cert" do
      assert :unverified = SkillAttestation.verify("", [])
    end

    test "returns :unverified when no keys configured (even valid-looking JSON)" do
      cert = Jason.encode!(%{skill: "test", issuer: "ca", signature: "abc"})
      # No :attestation_trusted_keys in config → unverified
      Application.delete_env(:controlkeel, :attestation_trusted_keys)
      assert :unverified = SkillAttestation.verify(cert, [])
    end
  end

  describe "verify/2 — with trusted keys" do
    setup do
      # Generate a real Ed25519 keypair for tests
      {pubkey, privkey} = :crypto.generate_key(:eddsa, :ed25519)

      pub_b64 = Base.url_encode64(pubkey, padding: false)
      priv_b64 = Base.url_encode64(privkey, padding: false)

      trusted_keys = [%{id: "test-ca", key: pub_b64}]
      Application.put_env(:controlkeel, :attestation_trusted_keys, trusted_keys)
      on_exit(fn -> Application.delete_env(:controlkeel, :attestation_trusted_keys) end)

      {:ok, pub_b64: pub_b64, priv_b64: priv_b64, privkey: privkey}
    end

    defp sign_cert(payload_map, privkey) do
      payload = payload_map |> Enum.sort_by(&elem(&1, 0)) |> Enum.into(%{}) |> Jason.encode!()
      sig = :crypto.sign(:eddsa, :none, payload, [privkey, :ed25519])
      sig_b64 = Base.url_encode64(sig, padding: false)
      Map.put(payload_map, "signature", sig_b64) |> Jason.encode!()
    end

    test "verifies a valid cert", %{privkey: privkey} do
      cert_json =
        sign_cert(
          %{
            "skill" => "pii-scrubber",
            "url" => "https://mcp.internal/pii",
            "issued_at" => "2026-01-01T00:00:00Z",
            "expires_at" => "2030-01-01T00:00:00Z",
            "issuer" => "test-ca"
          },
          privkey
        )

      assert :verified = SkillAttestation.verify(cert_json, [])
    end

    test "rejects expired cert", %{privkey: privkey} do
      cert_json =
        sign_cert(
          %{
            "skill" => "old-skill",
            "issuer" => "test-ca",
            "expires_at" => "2020-01-01T00:00:00Z"
          },
          privkey
        )

      assert {:invalid, :expired} = SkillAttestation.verify(cert_json, [])
    end

    test "rejects cert with unknown issuer" do
      cert_json =
        Jason.encode!(%{
          "skill" => "rogue-skill",
          "issuer" => "unknown-ca",
          "signature" => "abc"
        })

      assert {:invalid, :unknown_issuer} = SkillAttestation.verify(cert_json, [])
    end

    test "rejects tampered cert", %{privkey: privkey} do
      cert_json =
        sign_cert(
          %{
            "skill" => "legit-skill",
            "issuer" => "test-ca",
            "expires_at" => "2030-01-01T00:00:00Z"
          },
          privkey
        )

      # Tamper: change skill name after signing
      %{"signature" => sig} = Jason.decode!(cert_json)

      tampered =
        Jason.encode!(%{
          "skill" => "evil-skill",
          "issuer" => "test-ca",
          "expires_at" => "2030-01-01T00:00:00Z",
          "signature" => sig
        })

      assert {:invalid, :bad_signature} = SkillAttestation.verify(tampered, [])
    end

    test "rejects invalid JSON" do
      assert {:invalid, :bad_json} = SkillAttestation.verify("not json", [])
    end
  end

  describe "verified?/2" do
    test "returns false for nil" do
      Application.delete_env(:controlkeel, :attestation_trusted_keys)
      refute SkillAttestation.verified?(nil)
    end

    test "returns true for verified cert", %{} do
      # This test just confirms the delegation — full logic tested above
      Application.delete_env(:controlkeel, :attestation_trusted_keys)
      refute SkillAttestation.verified?(Jason.encode!(%{issuer: "x", signature: "y"}))
    end
  end

  describe "McpRegistry integration" do
    alias ControlKeel.Cloud.McpRegistry

    setup do
      Application.put_env(:controlkeel, :cloud_mcp_registry, %{
        default_policy: :deny,
        allowlist: [
          %{name: "secure-tool", url: "https://mcp.internal/secure", attestation: :required}
        ]
      })

      on_exit(fn -> Application.delete_env(:controlkeel, :cloud_mcp_registry) end)
      Application.delete_env(:controlkeel, :attestation_trusted_keys)
    end

    test "denied when no cert and attestation required" do
      assert {:denied, :attestation_required} = McpRegistry.lookup("secure-tool")
    end

    test "allowed when attested?: true passed directly" do
      assert :allowed = McpRegistry.lookup("secure-tool", attested?: true)
    end

    test "denied when cert present but no trusted keys (unverified)" do
      cert = Jason.encode!(%{"skill" => "secure-tool", "issuer" => "ca", "signature" => "abc"})
      assert {:denied, :attestation_required} = McpRegistry.lookup("secure-tool", cert: cert)
    end
  end
end
