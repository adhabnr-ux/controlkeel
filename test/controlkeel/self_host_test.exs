defmodule ControlKeel.SelfHostTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.SelfHost

  @env_vars ~w(DATABASE_URL SECRET_KEY_BASE PHX_HOST
              CONTROLKEEL_NATS_URL CK_AUDIT_SIGNING_KEY
              CONTROLKEEL_OIDC_CLIENT_SECRET CONTROLKEEL_RUNTIME_MODE)

  setup do
    previous = Map.new(@env_vars, fn name -> {name, System.get_env(name)} end)
    Enum.each(@env_vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  describe "verify_environment/0" do
    test "reports all required env vars as missing when nothing is set" do
      result = SelfHost.verify_environment()

      refute result.ready?
      assert Enum.all?(result.required_env, &(&1.present? == false))
      assert Enum.map(result.required_env, & &1.name) == ~w(DATABASE_URL SECRET_KEY_BASE PHX_HOST)
    end

    test "marks required vars present when set, redacts the value", %{} do
      System.put_env("DATABASE_URL", "postgres://user:pw@host/db")
      System.put_env("SECRET_KEY_BASE", "super-secret-base-key-value-here")
      System.put_env("PHX_HOST", "ck.example")

      result = SelfHost.verify_environment()

      database = Enum.find(result.required_env, &(&1.name == "DATABASE_URL"))
      assert database.present?
      assert database.value_hint == "(set, post…)"
      refute database.value_hint =~ "user:pw"
    end

    test "reports the repo section with the current runtime mode" do
      previous_mode = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)

      on_exit(fn ->
        if previous_mode do
          Application.put_env(:controlkeel, :runtime_mode, previous_mode)
        else
          Application.delete_env(:controlkeel, :runtime_mode)
        end
      end)

      result = SelfHost.verify_environment()

      assert result.repo.mode == :local
      assert result.repo.error == nil
      assert is_boolean(result.repo.cloud_repo_enabled?)
      assert is_boolean(result.repo.repo_reachable?)
    end

    test "is ready when all required vars are present in local mode" do
      previous_mode = Application.get_env(:controlkeel, :runtime_mode)
      Application.put_env(:controlkeel, :runtime_mode, :local)
      System.put_env("DATABASE_URL", "x")
      System.put_env("SECRET_KEY_BASE", "x")
      System.put_env("PHX_HOST", "x")

      on_exit(fn ->
        if previous_mode do
          Application.put_env(:controlkeel, :runtime_mode, previous_mode)
        else
          Application.delete_env(:controlkeel, :runtime_mode)
        end
      end)

      result = SelfHost.verify_environment()
      assert result.ready?
    end

    test "is not ready in cloud mode without CloudRepo config" do
      previous_mode = Application.get_env(:controlkeel, :runtime_mode)
      previous_cloud_repo = Application.get_env(:controlkeel, ControlKeel.CloudRepo)

      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      # Defensive: clear any leaked CloudRepo config from earlier tests so
      # `Runtime.cloud_repo_enabled?/0` returns false here.
      Application.delete_env(:controlkeel, ControlKeel.CloudRepo)

      System.put_env("DATABASE_URL", "x")
      System.put_env("SECRET_KEY_BASE", "x")
      System.put_env("PHX_HOST", "x")

      on_exit(fn ->
        if previous_mode do
          Application.put_env(:controlkeel, :runtime_mode, previous_mode)
        else
          Application.delete_env(:controlkeel, :runtime_mode)
        end

        if previous_cloud_repo do
          Application.put_env(:controlkeel, ControlKeel.CloudRepo, previous_cloud_repo)
        else
          Application.delete_env(:controlkeel, ControlKeel.CloudRepo)
        end
      end)

      result = SelfHost.verify_environment()
      refute result.ready?
      assert result.repo.mode == :cloud
      assert is_binary(result.repo.error)
    end
  end

  describe "bundle_manifest/0" do
    test "includes the release output and migrations" do
      paths = SelfHost.bundle_manifest()
      assert "_build/prod/rel/controlkeel/" in paths
      assert "priv/repo/migrations/" in paths
      assert "INSTALL.md" in paths
    end

    test "every entry is a relative path string" do
      assert Enum.all?(SelfHost.bundle_manifest(), &is_binary/1)
      refute Enum.any?(SelfHost.bundle_manifest(), &String.starts_with?(&1, "/"))
    end
  end

  describe "install_guide/0" do
    test "renders Markdown including required env vars" do
      guide = SelfHost.install_guide()
      assert guide =~ "# ControlKeel self-host install"

      for name <- ~w(DATABASE_URL SECRET_KEY_BASE PHX_HOST) do
        assert guide =~ "`#{name}`"
      end
    end

    test "mentions verify command and air-gapped opt-in posture" do
      guide = SelfHost.install_guide()
      assert guide =~ "controlkeel selfhost verify"
      assert guide =~ "Telemetry sync stays disabled"
      assert guide =~ "CK_AUDIT_SIGNING_KEY"
    end
  end
end
