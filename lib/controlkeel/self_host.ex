defmodule ControlKeel.SelfHost do
  @moduledoc """
  Air-gapped / self-host packaging helpers.

  Three responsibilities for this first slice:

    1. `verify_environment/0` — report which required and recommended env vars
       are present, whether the cloud Repo is configured, and which runtime
       mode is active. Used by `controlkeel selfhost verify` so an operator
       can sanity-check a deployment before booting.
    2. `bundle_manifest/0` — declare which on-disk paths belong in an
       air-gapped install bundle (release tarball + migrations + skill
       priv data). Used by the manifest CLI command and by any future
       packager task (the actual tar creation is intentionally deferred —
       this slice only fixes the contract).
    3. `install_guide/0` — render a short, deterministic INSTALL.md whose
       text is governed by this module so an operator's deployment never
       drifts from the env-var contract.

  No actual filesystem writes happen here; this module is pure read + render.
  """

  alias ControlKeel.Repo
  alias ControlKeel.Runtime

  @required_env_vars ~w(DATABASE_URL SECRET_KEY_BASE PHX_HOST)
  @recommended_env_vars ~w(
    CONTROLKEEL_NATS_URL
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
          mode: :local | :cloud,
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
    2. (Optional, cloud mode) Provision NATS JetStream and set `CONTROLKEEL_NATS_URL`.
    3. Extract this bundle.
    4. Run `bin/controlkeel eval` to confirm the release loads.
    5. Run `bin/controlkeel migrate` to apply migrations.
    6. Run `bin/controlkeel start` to start the application.
    7. From outside the release, run `controlkeel selfhost verify` to confirm
       env vars and Repo reachability.

    ## Verifying readiness

    Run:

        controlkeel selfhost verify

    Required env vars must be present and (if cloud mode) the Repo must be reachable
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
        cond do
          not enabled? ->
            %{
              mode: :cloud,
              cloud_repo_enabled?: false,
              repo_reachable?: false,
              error: "cloud mode requires CloudRepo configuration"
            }

          true ->
            reachable = probe_repo()

            %{
              mode: :cloud,
              cloud_repo_enabled?: true,
              repo_reachable?: reachable,
              error: if(reachable, do: nil, else: "Repo did not respond")
            }
        end
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
