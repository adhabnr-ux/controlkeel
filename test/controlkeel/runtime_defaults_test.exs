defmodule ControlKeel.RuntimeDefaultsTest do
  use ExUnit.Case, async: false

  alias ControlKeel.RuntimeDefaults

  setup do
    tmp_home =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_home)
    File.mkdir_p!(tmp_home)
    on_exit(fn -> File.rm_rf!(tmp_home) end)

    {:ok, tmp_home: tmp_home}
  end

  test "database_path falls back to a local app-data directory", %{tmp_home: tmp_home} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-cwd-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(%{"DATABASE_PATH" => nil, "CONTROLKEEL_HOME" => tmp_home}, fn ->
      File.cd!(tmp_dir, fn ->
        path = RuntimeDefaults.database_path()

        refute String.starts_with?(path, tmp_dir)
        assert String.ends_with?(path, "controlkeel.db")
        assert File.dir?(Path.dirname(path))
      end)
    end)
  end

  test "database_path prefers a project-local sqlite db when inside a repo", %{tmp_home: tmp_home} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-project-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "lib/trial"))
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(%{"DATABASE_PATH" => nil, "CONTROLKEEL_HOME" => tmp_home}, fn ->
      File.cd!(tmp_dir, fn ->
        path = RuntimeDefaults.database_path()

        assert path == Path.join([File.cwd!(), "controlkeel", "controlkeel.db"])
      end)
    end)
  end

  test "maybe_seed_project_database seeds a fresh project db from the global db",
       %{tmp_home: tmp_home} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-seed-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(%{"DATABASE_PATH" => nil, "CONTROLKEEL_HOME" => tmp_home}, fn ->
      # Seed a legacy global db with a WAL sidecar and content.
      global = RuntimeDefaults.global_database_path()
      File.write!(global, "GLOBAL-DB-BYTES")
      File.write!(global <> "-wal", "WAL-BYTES")

      File.cd!(tmp_dir, fn ->
        project_path = RuntimeDefaults.database_path()
        refute File.exists?(project_path)

        assert RuntimeDefaults.maybe_seed_project_database() == :seeded

        assert File.read!(project_path) == "GLOBAL-DB-BYTES"
        assert File.read!(project_path <> "-wal") == "WAL-BYTES"
      end)
    end)
  end

  test "maybe_seed_project_database is a no-op when the project db already exists",
       %{tmp_home: tmp_home} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-seed-existing-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(%{"DATABASE_PATH" => nil, "CONTROLKEEL_HOME" => tmp_home}, fn ->
      global = RuntimeDefaults.global_database_path()
      File.write!(global, "GLOBAL-DB-BYTES")

      File.cd!(tmp_dir, fn ->
        project_path = RuntimeDefaults.database_path()
        File.mkdir_p!(Path.dirname(project_path))
        File.write!(project_path, "PROJECT-LOCAL-BYTES")

        assert RuntimeDefaults.maybe_seed_project_database() == :noop
        # Existing project db is left untouched.
        assert File.read!(project_path) == "PROJECT-LOCAL-BYTES"
      end)
    end)
  end

  test "maybe_seed_project_database is a no-op without a global db", %{tmp_home: tmp_home} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-seed-noglobal-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(%{"DATABASE_PATH" => nil, "CONTROLKEEL_HOME" => tmp_home}, fn ->
      File.cd!(tmp_dir, fn ->
        project_path = RuntimeDefaults.database_path()

        assert RuntimeDefaults.maybe_seed_project_database() == :noop
        refute File.exists?(project_path)
      end)
    end)
  end

  test "maybe_seed_project_database is a no-op when DATABASE_PATH is set",
       %{tmp_home: tmp_home} do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "controlkeel-runtime-defaults-seed-explicit-#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(tmp_dir)
    File.mkdir_p!(tmp_dir)
    File.write!(Path.join(tmp_dir, "mix.exs"), "defmodule Trial.MixProject do\nend\n")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    with_envs(
      %{"DATABASE_PATH" => Path.join(tmp_dir, "explicit.db"), "CONTROLKEEL_HOME" => tmp_home},
      fn ->
        global = RuntimeDefaults.global_database_path()
        File.write!(global, "GLOBAL-DB-BYTES")

        File.cd!(tmp_dir, fn ->
          assert RuntimeDefaults.maybe_seed_project_database() == :noop
          refute File.exists?(Path.join([tmp_dir, "controlkeel", "controlkeel.db"]))
        end)
      end
    )
  end

  test "secret_key_base is generated once and then reused", %{tmp_home: tmp_home} do
    with_envs(%{"SECRET_KEY_BASE" => nil, "HOME" => tmp_home}, fn ->
      first = RuntimeDefaults.secret_key_base()
      second = RuntimeDefaults.secret_key_base()

      assert first == second
      assert byte_size(first) > 40
    end)
  end

  test "endpoint_url_config defaults to local values" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => nil,
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => nil
      },
      fn ->
        assert RuntimeDefaults.endpoint_url_config() ==
                 [host: "localhost", scheme: "http", port: 4000]
      end
    )
  end

  test "endpoint_url_config defaults to cloud values" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "cloud",
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => nil
      },
      fn ->
        assert RuntimeDefaults.endpoint_url_config() ==
                 [host: "controlkeel.com", scheme: "https", port: 443]
      end
    )
  end

  test "endpoint_url_config applies host, scheme, and port overrides" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "local",
        "PHX_HOST" => "example.test",
        "PHX_URL_SCHEME" => "https",
        "PHX_URL_PORT" => "8443"
      },
      fn ->
        assert RuntimeDefaults.endpoint_url_config() ==
                 [host: "example.test", scheme: "https", port: 8443]
      end
    )
  end

  test "endpoint_url_config falls back when PHX_URL_PORT is invalid" do
    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "cloud",
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => "not-a-number"
      },
      fn ->
        assert RuntimeDefaults.endpoint_url_config() ==
                 [host: "controlkeel.com", scheme: "https", port: 443]
      end
    )

    with_envs(
      %{
        "CONTROLKEEL_RUNTIME_MODE" => "local",
        "PHX_HOST" => nil,
        "PHX_URL_SCHEME" => nil,
        "PHX_URL_PORT" => "0"
      },
      fn ->
        assert RuntimeDefaults.endpoint_url_config() ==
                 [host: "localhost", scheme: "http", port: 4000]
      end
    )
  end

  defp with_envs(changes, fun) do
    previous =
      Enum.into(changes, %{}, fn {key, _value} -> {key, System.get_env(key)} end)

    try do
      Enum.each(changes, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      fun.()
    after
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
