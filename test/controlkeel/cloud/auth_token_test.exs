defmodule ControlKeel.Cloud.AuthTokenTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.AuthToken
  alias ControlKeel.Cloud.WorkspaceIdentity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-authtoken-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_home)
    previous_home = System.get_env("CONTROLKEEL_HOME")
    System.put_env("CONTROLKEEL_HOME", tmp_home)

    on_exit(fn ->
      if previous_home do
        System.put_env("CONTROLKEEL_HOME", previous_home)
      else
        System.delete_env("CONTROLKEEL_HOME")
      end

      File.rm_rf!(tmp_home)
    end)

    {:ok, identity, :created} = WorkspaceIdentity.ensure()
    {:ok, identity: identity}
  end

  describe "sign/2 + verify/1 round-trip" do
    test "verifies a freshly signed token", %{identity: identity} do
      {:ok, token} = AuthToken.sign(identity)

      assert {:ok, claims} = AuthToken.verify(token)
      assert claims.workspace_id == identity.workspace_id
      assert %DateTime{} = claims.issued_at
      assert %DateTime{} = claims.expires_at
      assert DateTime.compare(claims.expires_at, claims.issued_at) == :gt
    end

    test "two signs in quick succession produce different tokens (nonce)", %{identity: identity} do
      {:ok, t1} = AuthToken.sign(identity)
      {:ok, t2} = AuthToken.sign(identity)
      refute t1 == t2
    end

    test "honors a custom ttl_seconds", %{identity: identity} do
      {:ok, token} = AuthToken.sign(identity, ttl_seconds: 30)
      {:ok, claims} = AuthToken.verify(token)

      delta = DateTime.diff(claims.expires_at, claims.issued_at, :second)
      assert delta == 30
    end
  end

  describe "verify/1 failure cases" do
    test "rejects nil and empty strings" do
      assert {:error, :missing_token} = AuthToken.verify(nil)
      assert {:error, :missing_token} = AuthToken.verify("")
    end

    test "rejects malformed tokens" do
      assert {:error, :malformed} = AuthToken.verify("not-a-token")
      assert {:error, :malformed} = AuthToken.verify("only.one.dot.too.many")
      assert {:error, :malformed} = AuthToken.verify("abc.def")
    end

    test "rejects an expired token", %{identity: identity} do
      {:ok, token} = AuthToken.sign(identity, ttl_seconds: -10)
      assert {:error, :expired} = AuthToken.verify(token)
    end

    test "rejects a tampered payload", %{identity: identity} do
      {:ok, token} = AuthToken.sign(identity)
      [payload_b64, sig_b64] = String.split(token, ".")

      tampered_payload = payload_b64 |> Base.url_decode64!(padding: false)
      first = :binary.first(tampered_payload)
      flip = if first == ?X, do: ?Y, else: ?X
      tampered = <<flip>> <> binary_part(tampered_payload, 1, byte_size(tampered_payload) - 1)
      tampered_b64 = Base.url_encode64(tampered, padding: false)

      assert {:error, reason} = AuthToken.verify("#{tampered_b64}.#{sig_b64}")
      assert reason in [:bad_signature, :malformed, :unknown_workspace]
    end

    test "rejects a tampered signature", %{identity: identity} do
      {:ok, token} = AuthToken.sign(identity)
      [payload_b64, sig_b64] = String.split(token, ".")

      first = String.first(sig_b64)
      replacement = if first == "A", do: "B", else: "A"
      tampered_sig = replacement <> String.slice(sig_b64, 1..-1//1)

      assert {:error, reason} = AuthToken.verify("#{payload_b64}.#{tampered_sig}")
      assert reason in [:bad_signature, :malformed]
    end

    test "rejects a token whose workspace doesn't match the local identity", %{identity: identity} do
      {:ok, token} = AuthToken.sign(identity)

      # Replace the local identity with a different one (simulates a foreign workspace's token)
      {:ok, _new_identity, :rotated} = WorkspaceIdentity.ensure(force: true)

      assert {:error, :unknown_workspace} = AuthToken.verify(token)
    end
  end
end
