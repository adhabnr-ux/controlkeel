defmodule ControlKeel.Runtime.Defaults do
  @moduledoc false

  @app_dir_name "controlkeel"
  @secret_file_name "secret_key_base"

  def app_data_dir do
    path =
      case :os.type() do
        {:win32, _} ->
          Path.join(System.get_env("LOCALAPPDATA") || default_home(), "ControlKeel")

        {:unix, :darwin} ->
          Path.join([default_home(), "Library", "Application Support", "ControlKeel"])

        _ ->
          Path.join(
            System.get_env("XDG_DATA_HOME") || Path.join(default_home(), ".local/share"),
            @app_dir_name
          )
      end

    ensure_dir!(path)
  end

  def database_path do
    System.get_env("DATABASE_PATH") ||
      project_database_path(File.cwd!()) ||
      global_database_path()
  end

  @doc """
  Path to the legacy global database under the OS app-data directory. This was
  the only database location before the project-local pivot, so it is the source
  we migrate from for upgrading users.
  """
  def global_database_path do
    Path.join(app_data_dir(), "controlkeel.db")
  end

  @doc """
  One-time migration for the global -> project-local database pivot.

  When CK resolves to a project-local database that does not exist yet, but a
  legacy global database with data is present, copy the global database (and its
  WAL/SHM sidecars) into the project path so upgrading users keep their history
  instead of landing in an empty database. No-op once the project database
  exists, when `DATABASE_PATH` is set explicitly, when CK is not inside a
  project, or when the global database is absent/empty.

  Must run before the Repo opens the database (call it from config/runtime.exs
  after computing the path, before configuring the Repo). Returns `:seeded`,
  `:noop`, or `:error`.
  """
  def maybe_seed_project_database do
    if System.get_env("DATABASE_PATH") in [nil, ""] do
      case project_database_path(File.cwd!()) do
        nil -> :noop
        project_path -> maybe_seed(project_path, global_database_path())
      end
    else
      :noop
    end
  end

  defp maybe_seed(project_path, global_path) do
    cond do
      File.exists?(project_path) -> :noop
      not regular_file_with_data?(global_path) -> :noop
      true -> seed_from_global(project_path, global_path)
    end
  end

  defp regular_file_with_data?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size > 0 -> true
      _ -> false
    end
  end

  # Copy the global database plus its WAL/SHM sidecars as a set so SQLite can
  # replay any not-yet-checkpointed transactions. On any failure, remove the
  # partial copy so the next boot retries (or starts fresh) rather than opening a
  # half-written database.
  defp seed_from_global(project_path, global_path) do
    File.mkdir_p!(Path.dirname(project_path))

    Enum.each(["", "-wal", "-shm"], fn suffix ->
      src = global_path <> suffix
      if File.exists?(src), do: File.cp!(src, project_path <> suffix)
    end)

    notify("[controlkeel] migrated existing data: #{global_path} -> #{project_path}")
    :seeded
  rescue
    error ->
      Enum.each(["", "-wal", "-shm"], &File.rm_rf!(project_path <> &1))

      notify(
        "[controlkeel] could not migrate global database (#{Exception.message(error)}); starting with a fresh project database"
      )

      :error
  end

  # stdout is reserved for MCP JSON-RPC framing, so migration notices go to
  # stderr. This also runs during config/runtime.exs evaluation, before the
  # Logger application is guaranteed to be started.
  defp notify(message), do: IO.puts(:stderr, message)

  def secret_key_base do
    System.get_env("SECRET_KEY_BASE") || read_or_create_secret()
  end

  def endpoint_url_config do
    runtime_mode = runtime_mode()
    {default_host, default_scheme, default_port} = endpoint_defaults(runtime_mode)

    [
      host: env_or_default("PHX_HOST", default_host),
      scheme: env_or_default("PHX_URL_SCHEME", default_scheme),
      port: endpoint_port(default_port)
    ]
  end

  defp read_or_create_secret do
    path = Path.join(app_data_dir(), @secret_file_name)

    case File.read(path) do
      {:ok, secret} ->
        String.trim(secret)

      {:error, :enoent} ->
        secret = generate_secret()
        File.write!(path, secret <> "\n")
        secret
    end
  end

  defp generate_secret do
    64
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp runtime_mode do
    ControlKeel.Runtime.Mode.current()
  end

  defp endpoint_defaults(:cloud), do: {"controlkeel.com", "https", 443}
  defp endpoint_defaults(:self_hosted), do: {"localhost", "https", 443}
  defp endpoint_defaults(:local), do: {"localhost", "http", 4000}

  defp env_or_default(key, default) do
    case System.get_env(key) do
      nil -> default
      "" -> default
      value -> value
    end
  end

  defp endpoint_port(default_port) do
    case System.get_env("PHX_URL_PORT") do
      nil -> default_port
      "" -> default_port
      value -> parse_positive_integer(value, default_port)
    end
  end

  defp parse_positive_integer(value, fallback) do
    case Integer.parse(value) do
      {port, ""} when port > 0 -> port
      _ -> fallback
    end
  end

  # CONTROLKEEL_HOME relocates the app-data root and is read at runtime (unlike
  # OS HOME, which OTP caches at VM boot). Honoring it keeps the data directory
  # overridable in production and lets tests redirect app-data writes without
  # touching the real user home. Same convention used by ck_token_audit.
  defp default_home do
    case System.get_env("CONTROLKEEL_HOME") do
      home when is_binary(home) and home != "" -> home
      _ -> System.user_home!()
    end
  end

  defp project_database_path(cwd) do
    root = ControlKeel.Project.Root.resolve(cwd)

    if ControlKeel.Project.Root.project_root?(root) do
      Path.join([root, "controlkeel", "controlkeel.db"])
    end
  end

  defp ensure_dir!(path) do
    File.mkdir_p!(path)
    path
  end
end
