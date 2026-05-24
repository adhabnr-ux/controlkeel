defmodule ControlKeel.Cloud.WorkspaceIdentityTest do
  use ExUnit.Case, async: false

  alias ControlKeel.Cloud.WorkspaceIdentity

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-workspace-identity-#{System.unique_integer([:positive])}"
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

    {:ok, tmp_home: tmp_home}
  end

  describe "ensure/1 first run" do
    test "creates a new identity when none exists" do
      refute WorkspaceIdentity.connected?()

      assert {:ok, identity, :created} = WorkspaceIdentity.ensure()

      assert String.starts_with?(identity.workspace_id, "ws_")
      assert identity.algorithm == "ed25519"
      assert String.length(identity.fingerprint) == 64
      assert is_binary(identity.public_key)
      assert is_binary(identity.private_key)
      assert %DateTime{} = identity.created_at
      assert WorkspaceIdentity.connected?()
    end

    test "persists the identity to disk with 0600 permissions" do
      {:ok, identity, :created} = WorkspaceIdentity.ensure()

      assert File.exists?(identity.path)

      {:ok, stat} = File.stat(identity.path)
      # File.stat returns mode including type bits; mask to permission bits
      perm = Bitwise.band(stat.mode, 0o777)
      assert perm == 0o600
    end
  end

  describe "ensure/1 idempotence" do
    test "returns the existing identity on subsequent calls" do
      {:ok, first, :created} = WorkspaceIdentity.ensure()
      {:ok, second, :existing} = WorkspaceIdentity.ensure()

      assert first.workspace_id == second.workspace_id
      assert first.fingerprint == second.fingerprint
      assert first.public_key == second.public_key
    end

    test "force: true rotates the keypair and assigns a new workspace ID" do
      {:ok, first, :created} = WorkspaceIdentity.ensure()
      {:ok, second, :rotated} = WorkspaceIdentity.ensure(force: true)

      refute first.workspace_id == second.workspace_id
      refute first.fingerprint == second.fingerprint
      refute first.public_key == second.public_key
    end
  end

  describe "load/0" do
    test "returns :not_connected when no identity has been generated" do
      assert {:error, :not_connected} = WorkspaceIdentity.load()
    end

    test "returns the persisted identity after ensure" do
      {:ok, created, :created} = WorkspaceIdentity.ensure()
      {:ok, loaded} = WorkspaceIdentity.load()

      assert loaded.workspace_id == created.workspace_id
      assert loaded.fingerprint == created.fingerprint
      assert loaded.algorithm == "ed25519"
    end

    test "returns :malformed when the file is invalid JSON" do
      File.mkdir_p!(Path.dirname(WorkspaceIdentity.path()))
      File.write!(WorkspaceIdentity.path(), "not json")

      assert {:error, {:malformed, _}} = WorkspaceIdentity.load()
    end

    test "returns :malformed when required fields are missing" do
      File.mkdir_p!(Path.dirname(WorkspaceIdentity.path()))
      File.write!(WorkspaceIdentity.path(), Jason.encode!(%{"workspace_id" => "ws_xyz"}))

      assert {:error, {:malformed, _}} = WorkspaceIdentity.load()
    end

    test "returns :malformed when algorithm is unsupported" do
      File.mkdir_p!(Path.dirname(WorkspaceIdentity.path()))

      File.write!(
        WorkspaceIdentity.path(),
        Jason.encode!(%{
          "workspace_id" => "ws_x",
          "algorithm" => "rsa-4096",
          "public_key" => "x",
          "private_key" => "y",
          "fingerprint" => "z",
          "created_at" => "2026-05-23T20:00:00Z"
        })
      )

      assert {:error, {:malformed, msg}} = WorkspaceIdentity.load()
      assert msg =~ "unsupported algorithm"
    end
  end

  describe "short_fingerprint/1" do
    test "returns the first 16 hex chars" do
      assert WorkspaceIdentity.short_fingerprint("0123456789abcdef" <> String.duplicate("0", 48)) ==
               "0123456789abcdef"
    end

    test "accepts an identity struct" do
      {:ok, identity, :created} = WorkspaceIdentity.ensure()
      assert String.length(WorkspaceIdentity.short_fingerprint(identity)) == 16
    end
  end
end
