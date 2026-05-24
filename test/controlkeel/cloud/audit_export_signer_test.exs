defmodule ControlKeel.Cloud.AuditExportSignerTest do
  use ExUnit.Case, async: true

  alias ControlKeel.Cloud.AuditExportSigner

  test "digest is deterministic for map key order" do
    left = %{"b" => 2, "a" => %{"z" => 1, "m" => [2, 1]}}
    right = %{"a" => %{"m" => [2, 1], "z" => 1}, "b" => 2}

    assert AuditExportSigner.canonical_json(left) == AuditExportSigner.canonical_json(right)
    assert AuditExportSigner.digest(left) == AuditExportSigner.digest(right)
  end

  test "sign wraps payload and verifies with the same key" do
    envelope = AuditExportSigner.sign(%{"a" => 1}, "test-key", key_id: "TEST_KEY", signed_at: ~U[2026-01-01 00:00:00Z])

    assert envelope["kind"] == "controlkeel.audit_export.signed"
    assert envelope["integrity"]["key_id"] == "TEST_KEY"
    assert envelope["integrity"]["digest_algorithm"] == "sha256"
    assert envelope["integrity"]["signature_algorithm"] == "hmac-sha256"
    assert :ok = AuditExportSigner.verify(envelope, "test-key")
  end

  test "verify detects modified payload" do
    envelope = AuditExportSigner.sign(%{"a" => 1}, "test-key")
    tampered = put_in(envelope, ["payload", "a"], 2)

    assert {:error, :digest_mismatch} = AuditExportSigner.verify(tampered, "test-key")
  end

  test "verify detects wrong key" do
    envelope = AuditExportSigner.sign(%{"a" => 1}, "test-key")
    assert {:error, :signature_mismatch} = AuditExportSigner.verify(envelope, "other-key")
  end
end
