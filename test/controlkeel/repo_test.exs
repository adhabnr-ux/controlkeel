defmodule ControlKeel.RepoTest do
  use ControlKeel.DataCase, async: false

  alias ControlKeel.{Repo, Runtime}

  # `Repo.active/0` is the routing primitive that issue #44 hinged on. If it
  # silently resolves to SQLite in cloud mode, every context module in the
  # app reads and writes the wrong database.
  describe "active/0 routing" do
    setup do
      prev_runtime_mode = Application.get_env(:controlkeel, :runtime_mode)
      prev_cloud_repo = Application.get_env(:controlkeel, ControlKeel.CloudRepo)
      prev_mode_env = System.get_env("CONTROLKEEL_RUNTIME_MODE")

      on_exit(fn ->
        if prev_runtime_mode do
          Application.put_env(:controlkeel, :runtime_mode, prev_runtime_mode)
        else
          Application.delete_env(:controlkeel, :runtime_mode)
        end

        if prev_cloud_repo do
          Application.put_env(:controlkeel, ControlKeel.CloudRepo, prev_cloud_repo)
        else
          Application.delete_env(:controlkeel, ControlKeel.CloudRepo)
        end

        if prev_mode_env,
          do: System.put_env("CONTROLKEEL_RUNTIME_MODE", prev_mode_env),
          else: System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      end)

      :ok
    end

    test "resolves to the local SQLite repo in :local mode" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      Application.delete_env(:controlkeel, ControlKeel.CloudRepo)

      assert Runtime.mode() == :local
      assert Repo.active() == ControlKeel.Repo.Local
    end

    test "resolves to CloudRepo when cloud mode is enabled and configured" do
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      Application.put_env(:controlkeel, ControlKeel.CloudRepo, url: "postgresql://placeholder")

      assert Runtime.mode() == :cloud
      assert Runtime.cloud_repo_enabled?()
      assert Repo.active() == ControlKeel.CloudRepo
    end

    test "fails closed to SQLite when cloud mode is set but CloudRepo is unconfigured" do
      # Mirrors Runtime.cloud_repo_enabled?/0: a cloud deploy missing the
      # DATABASE_URL config must NOT route to a half-initialized CloudRepo.
      # Tests assert the primitive; the deploy-time failure mode is covered by
      # `cloud doctor` and the runtime.exs raise.
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      Application.put_env(:controlkeel, :runtime_mode, :cloud)
      Application.delete_env(:controlkeel, ControlKeel.CloudRepo)

      assert Runtime.mode() == :cloud
      refute Runtime.cloud_repo_enabled?()
      assert Repo.active() == ControlKeel.Repo.Local
    end

    test "resolves to CloudRepo for :self_hosted mode when CloudRepo is configured" do
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)
      Application.put_env(:controlkeel, ControlKeel.CloudRepo, url: "postgresql://placeholder")

      assert Runtime.mode() == :self_hosted
      assert Runtime.cloud_repo_enabled?()
      assert Repo.active() == ControlKeel.CloudRepo
    end

    test "resolves to SQLite for :self_hosted when CloudRepo has no :url (issue #44)" do
      # config/config.exs always sets CloudRepo priv: "priv/repo", so a bare
      # non-empty CloudRepo env must NOT count as "enabled". A self-hosted box
      # without DATABASE_URL must keep using the SQLite database runtime.exs
      # configured, rather than routing queries to an unconfigured Postgres repo.
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")
      Application.put_env(:controlkeel, :runtime_mode, :self_hosted)
      Application.put_env(:controlkeel, ControlKeel.CloudRepo, priv: "priv/repo")

      assert Runtime.mode() == :self_hosted
      refute Runtime.cloud_repo_enabled?()
      assert Repo.active() == ControlKeel.Repo.Local
    end
  end

  describe "Runtime.local_repo_configured?/0" do
    # Gates whether Repo.Local is supervised. A prod cloud release leaves
    # Repo.Local without :database/:url, so the predicate must report false to
    # avoid booting an unconfigured SQLite repo (issue #44).
    setup do
      prev = Application.get_env(:controlkeel, ControlKeel.Repo.Local)

      on_exit(fn ->
        case prev do
          nil ->
            Application.delete_env(:controlkeel, ControlKeel.Repo.Local)

          config ->
            Application.put_env(:controlkeel, ControlKeel.Repo.Local, config, persistent: true)
        end
      end)

      :ok
    end

    test "true when a :database is present" do
      Application.put_env(:controlkeel, ControlKeel.Repo.Local, database: "/tmp/x.db")
      assert Runtime.local_repo_configured?()
    end

    test "true when a :url is present" do
      Application.put_env(:controlkeel, ControlKeel.Repo.Local, url: "postgresql://x")
      assert Runtime.local_repo_configured?()
    end

    test "false with only non-connection config (mirrors prod cloud)" do
      Application.put_env(:controlkeel, ControlKeel.Repo.Local, priv: "priv/repo")
      refute Runtime.local_repo_configured?()
    end
  end

  describe "forwarded queries (local mode)" do
    # Confirms the dispatcher actually hands off to the underlying repo for the
    # common query path, not just resolves the module.
    test "Repo.all/1 reaches Repo.Local" do
      Application.put_env(:controlkeel, :runtime_mode, :local)
      System.delete_env("CONTROLKEEL_RUNTIME_MODE")

      assert Repo.active() == ControlKeel.Repo.Local

      # Sanity: a call through the dispatcher does not raise and matches the
      # underlying repo's result for an empty table.
      assert Repo.all(ControlKeel.Mission.Session) ==
               ControlKeel.Repo.Local.all(ControlKeel.Mission.Session)
    end
  end
end
