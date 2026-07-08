defmodule ControlKeel.Ops.SelfHost do
  @moduledoc """
  Air-gapped / self-host packaging helpers.

  Main responsibilities:

    1. `verify_environment/0` — report which required and recommended env vars
       are present, whether the cloud Repo is configured, and which runtime
       mode is active. Used by `controlkeel selfhost verify` so an operator
       can sanity-check a deployment before booting.
    2. `bundle_manifest/0` and `pack/2` — declare and package the on-disk paths
       that belong in an air-gapped install bundle (release tarball + migrations
       + skill priv data).
    3. `install_guide/0` — render a short, deterministic INSTALL.md whose
       text is governed by this module so an operator's deployment never
       drifts from the env-var contract.
  """

  alias ControlKeel.Repo
  alias ControlKeel.Runtime

  @required_env_vars ~w(DATABASE_URL SECRET_KEY_BASE PHX_HOST)
  @recommended_env_vars ~w(
    CK_AUDIT_SIGNING_KEY
    CONTROLKEEL_OIDC_CLIENT_SECRET
    CONTROLKEEL_RUNTIME_MODE
  )

  @manifest_paths [
    "_build/prod/rel/controlkeel/",
    "priv/repo/migrations/",
    "priv/skills/",
    "priv/static/",
    "config/runtime.exs",
    "INSTALL.md"
  ]

  @typedoc "Environment check outcome."
  @type env_check :: %{
          name: String.t(),
          severity: :required | :recommended,
          present?: boolean(),
          value_hint: String.t() | nil
        }

  @typedoc "Repo reachability outcome."
  @type repo_check :: %{
          mode: :local | :cloud | :self_hosted,
          cloud_repo_enabled?: boolean(),
          repo_reachable?: boolean(),
          error: String.t() | nil
        }

  @typedoc "Verify result aggregate."
  @type verify_result :: %{
          required_env: [env_check()],
          recommended_env: [env_check()],
          repo: repo_check(),
          ready?: boolean()
        }

  @doc "Inspect the current process env + Repo state for self-host readiness."
  @spec verify_environment() :: verify_result()
  def verify_environment do
    required = Enum.map(@required_env_vars, &check_env(&1, :required))
    recommended = Enum.map(@recommended_env_vars, &check_env(&1, :recommended))
    repo = check_repo()

    ready? =
      Enum.all?(required, & &1.present?) and
        repo.error == nil and
        (Runtime.local?() or repo.repo_reachable?)

    %{
      required_env: required,
      recommended_env: recommended,
      repo: repo,
      ready?: ready?
    }
  end

  @doc "Declare the on-disk paths that belong in an air-gapped install bundle."
  @spec bundle_manifest() :: [String.t()]
  def bundle_manifest, do: @manifest_paths

  @doc """
  Build an air-gapped install bundle by taring the `bundle_manifest/0` paths.

  `project_root` — the repo root to tar from (defaults to `File.cwd!/0`).

  Options:
    - `:output` — output path for the `.tar.gz` (default: `./controlkeel-release.tar.gz`)

  Returns `{:ok, %{path: path, sha256: hex}}` on success, or
  `{:error, reason}` on failure (missing release, write error, etc.).
  """
  @spec pack(String.t(), keyword()) ::
          {:ok, %{path: String.t(), sha256: String.t()}} | {:error, String.t()}
  def pack(project_root \\ File.cwd!(), opts \\ []) do
    root = Path.expand(project_root)
    output = Keyword.get(opts, :output, Path.join(root, "controlkeel-release.tar.gz"))

    release_dir = Path.join(root, "_build/prod/rel/controlkeel")

    unless File.dir?(release_dir) do
      {:error,
       "Release artifact not found at #{release_dir}. Run `MIX_ENV=prod mix release` first."}
    else
      paths =
        @manifest_paths
        |> Enum.map(&Path.join(root, &1))
        |> Enum.filter(&(File.exists?(&1) or File.dir?(&1)))
        |> Enum.map(&Path.relative_to(&1, root))

      case paths do
        [] ->
          {:error, "No manifest paths exist under #{root}. Nothing to pack."}

        file_list ->
          with :ok <- File.mkdir_p(Path.dirname(output)),
               :ok <- create_tarball(root, output, file_list) do
            sha256 = sha256_file(output)
            {:ok, %{path: output, sha256: sha256}}
          else
            {:error, reason} -> {:error, "Failed to write tarball: #{inspect(reason)}"}
          end
      end
    end
  end

  defp create_tarball(root, output, file_list) do
    # Build a list of {charlist_filename, binary_content} tuples for :erl_tar
    entries =
      file_list
      |> Enum.flat_map(&expand_path(Path.join(root, &1), &1))
      |> Enum.reject(fn {_name, content} -> is_nil(content) end)

    case :erl_tar.create(String.to_charlist(output), entries, [:compressed]) do
      :ok -> zero_gzip_mtime(output)
      {:error, reason} -> {:error, reason}
    end
  end

  # Gzip format embeds a 4-byte MTIME at offset 4 (bytes 4–7) in the header.
  # Two packs of identical content at different wall-clock seconds produce
  # different MTIME values and therefore different sha256. Zero the field so
  # the sha256 reflects only content, enabling deterministic integrity checking.
  defp zero_gzip_mtime(path) do
    with {:ok, data} <- File.read(path),
         true <- byte_size(data) >= 10 do
      zeroed =
        :binary.part(data, 0, 4) <>
          <<0, 0, 0, 0>> <>
          :binary.part(data, 8, byte_size(data) - 8)

      File.write!(path, zeroed)
      :ok
    else
      _ -> :ok
    end
  end

  defp expand_path(full_path, relative) do
    cond do
      File.regular?(full_path) ->
        case File.read(full_path) do
          {:ok, content} -> [{String.to_charlist(relative), content}]
          _ -> []
        end

      File.dir?(full_path) ->
        full_path
        |> File.ls!()
        |> Enum.flat_map(fn name ->
          expand_path(Path.join(full_path, name), Path.join(relative, name))
        end)

      true ->
        []
    end
  end

  defp sha256_file(path) do
    path
    |> File.stream!([], 65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), fn chunk, state ->
      :crypto.hash_update(state, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  @doc "Render the installation guide as a Markdown string."
  @spec install_guide() :: String.t()
  def install_guide do
    required = Enum.map_join(@required_env_vars, "\n", &"- `#{&1}`")
    recommended = Enum.map_join(@recommended_env_vars, "\n", &"- `#{&1}`")

    """
    # ControlKeel self-host install

    This bundle contains everything needed to run ControlKeel on a private network.

    ## Required environment

    #{required}

    ## Recommended environment

    #{recommended}

    ## Boot order

    1. Provision Postgres and set `DATABASE_URL`.
    2. Extract this bundle.
    3. Run `bin/controlkeel eval` to confirm the release loads.
    4. Run `bin/controlkeel migrate` to apply migrations.
    5. Run `bin/controlkeel start` to start the application.
    6. From outside the release, run `controlkeel selfhost verify` to confirm
       env vars and Repo reachability.

    ## Verifying readiness

    Run:

        controlkeel selfhost verify

    Required env vars must be present and (if cloud/self-hosted mode) the Repo must be reachable
    before serving traffic.

    ## Air-gapped notes

    - No outbound network requests are required to boot.
    - Telemetry sync stays disabled unless an operator opts in via
      `controlkeel telemetry enable --level <name>`.
    - Audit export bundles can be signed locally with `--sign` and any HMAC key
      supplied through `CK_AUDIT_SIGNING_KEY`.

    """
  end

  defp check_env(name, severity) do
    case System.get_env(name) do
      nil ->
        %{name: name, severity: severity, present?: false, value_hint: nil}

      "" ->
        %{name: name, severity: severity, present?: false, value_hint: nil}

      value ->
        %{
          name: name,
          severity: severity,
          present?: true,
          value_hint: redact_hint(value)
        }
    end
  end

  defp redact_hint(value) when byte_size(value) <= 6, do: "(set)"
  defp redact_hint(value), do: "(set, " <> String.slice(value, 0, 4) <> "…)"

  defp check_repo do
    mode = Runtime.mode()
    enabled? = Runtime.cloud_repo_enabled?()

    case mode do
      :local ->
        %{
          mode: :local,
          cloud_repo_enabled?: enabled?,
          repo_reachable?: probe_repo(),
          error: nil
        }

      :cloud ->
        remote_repo_check(:cloud, enabled?, "cloud mode requires CloudRepo configuration")

      :self_hosted ->
        remote_repo_check(
          :self_hosted,
          enabled?,
          "self-hosted mode requires CloudRepo configuration"
        )
    end
  end

  defp remote_repo_check(mode, enabled?, missing_message) do
    if enabled? do
      reachable = probe_repo()

      %{
        mode: mode,
        cloud_repo_enabled?: true,
        repo_reachable?: reachable,
        error: if(reachable, do: nil, else: "Repo did not respond")
      }
    else
      %{
        mode: mode,
        cloud_repo_enabled?: false,
        repo_reachable?: false,
        error: missing_message
      }
    end
  end

  defp probe_repo do
    Repo.query!("SELECT 1", [], log: false)
    true
  rescue
    _ -> false
  catch
    _, _ -> false
  end
end
