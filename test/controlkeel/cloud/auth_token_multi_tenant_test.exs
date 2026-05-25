defmodule ControlKeel.Cloud.AuthTokenMultiTenantTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.Cloud.AuthToken
  alias ControlKeel.Cloud.WorkspaceKeyRegistry

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-authtoken-mt-test-#{System.unique_integer([:positive])}"
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

    :ok
  end

  defp fresh_identity do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)

    %{
      workspace_id:
        "ws_" <> Base.encode32(:crypto.strong_rand_bytes(8), padding: false, case: :lower),
      algorithm: "ed25519",
      public_key: Base.encode64(pub),
      private_key: Base.encode64(priv),
      fingerprint: :crypto.hash(:sha256, pub) |> Base.encode16(case: :lower)
    }
  end

  describe "verify/1 with registry-backed lookup" do
    test "verifies a token whose pubkey lives in the registry, not local identity" do
      remote = fresh_identity()

      {:ok, _} =
        WorkspaceKeyRegistry.enroll(%{
          workspace_id: remote.workspace_id,
          public_key: remote.public_key,
          algorithm: remote.algorithm,
          fingerprint: remote.fingerprint,
          name: "remote-laptop",
          org_id: nil
        })

      {:ok, token} = AuthToken.sign(remote)
      assert {:ok, claims} = AuthToken.verify(token)
      assert claims.workspace_id == remote.workspace_id
    end

    test "successful verify touches last_seen_at on the registered row" do
      remote = fresh_identity()

      {:ok, %{last_seen_at: before}} =
        WorkspaceKeyRegistry.enroll(%{
          workspace_id: remote.workspace_id,
          public_key: remote.public_key,
          algorithm: remote.algorithm,
          fingerprint: remote.fingerprint,
          name: "lab",
          org_id: nil
        })

      Process.sleep(1100)

      {:ok, token} = AuthToken.sign(remote)
      assert {:ok, _claims} = AuthToken.verify(token)

      {:ok, key} = WorkspaceKeyRegistry.fetch(remote.workspace_id)
      assert DateTime.compare(key.last_seen_at, before) == :gt
    end

    test "rejects a token signed by a key not in the registry and not local" do
      stranger = fresh_identity()
      {:ok, token} = AuthToken.sign(stranger)

      assert {:error, :unknown_workspace} = AuthToken.verify(token)
    end

    test "revoked registration causes verification to fail" do
      remote = fresh_identity()

      {:ok, _} =
        WorkspaceKeyRegistry.enroll(%{
          workspace_id: remote.workspace_id,
          public_key: remote.public_key,
          algorithm: remote.algorithm,
          fingerprint: remote.fingerprint,
          name: "to-revoke",
          org_id: nil
        })

      {:ok, _} = WorkspaceKeyRegistry.revoke(remote.workspace_id)

      {:ok, token} = AuthToken.sign(remote)
      assert {:error, :unknown_workspace} = AuthToken.verify(token)
    end
  end
end
