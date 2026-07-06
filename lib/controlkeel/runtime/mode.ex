defmodule ControlKeel.Runtime.Mode do
  @moduledoc """
  First-class runtime mode and surface-placement contract.

  ControlKeel supports three deployment postures:

    * `:local` — governed state and execution stay on the operator machine.
    * `:cloud` — the local device is a browser/thin CLI/bootstrap; governed
      workload surfaces run in the ControlKeel Cloud plane.
    * `:self_hosted` — cloud semantics, but against the operator's hosted
      ControlKeel data plane instead of `controlkeel.com`.

  This module is intentionally small and pure so every surface can consult the
  same placement contract before choosing a local or remote execution path.
  """

  @typedoc "Supported ControlKeel runtime modes."
  @type mode :: :local | :cloud | :self_hosted

  @typedoc "Execution placement for a governed surface."
  @type placement :: :local | :cloud | :self_hosted | :thin_client

  @surfaces ~w(db mcp skills hooks cli web memory policy telemetry observability sdk)a

  @doc "All governed surfaces covered by the runtime-placement contract."
  @spec surfaces() :: [atom()]
  def surfaces, do: @surfaces

  @doc "Parse runtime mode from env/config input. Unknown values fail safe to local."
  @spec parse(nil | atom() | String.t()) :: mode()
  def parse(nil), do: :local
  def parse(:local), do: :local
  def parse(:cloud), do: :cloud
  def parse(:self_hosted), do: :self_hosted
  def parse(:selfhost), do: :self_hosted

  def parse(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() do
      "cloud" -> :cloud
      "self_hosted" -> :self_hosted
      "self-hosted" -> :self_hosted
      "selfhost" -> :self_hosted
      "self_host" -> :self_hosted
      _ -> :local
    end
  end

  def parse(_), do: :local

  @doc "Resolve the current runtime mode from env, then application config."
  @spec current() :: mode()
  def current do
    case System.get_env("CONTROLKEEL_RUNTIME_MODE") do
      nil -> Application.get_env(:controlkeel, :runtime_mode, :local) |> parse()
      value -> parse(value)
    end
  end

  @doc "Return the placement for one governed surface in the given mode."
  @spec placement(mode(), atom()) :: placement()
  def placement(mode \\ current(), surface)
  def placement(:local, surface) when surface in @surfaces, do: :local
  def placement(:cloud, :cli), do: :thin_client
  def placement(:cloud, surface) when surface in @surfaces, do: :cloud
  def placement(:self_hosted, :cli), do: :thin_client
  def placement(:self_hosted, surface) when surface in @surfaces, do: :self_hosted
  def placement(_mode, _surface), do: :local

  @doc "Return placement for every governed surface in the given mode."
  @spec placement_map(mode()) :: %{atom() => placement()}
  def placement_map(mode \\ current()) do
    Map.new(@surfaces, &{&1, placement(mode, &1)})
  end

  @canonical_cloud_host "controlkeel.com"

  @doc "Canonical SaaS host for ControlKeel Cloud mode."
  @spec canonical_cloud_host() :: String.t()
  def canonical_cloud_host, do: @canonical_cloud_host

  @doc "Normalize and validate a configured cloud-sync base endpoint for a mode."
  @spec normalize_sync_endpoint(nil | String.t(), mode()) :: {:ok, String.t()} | {:error, atom()}
  def normalize_sync_endpoint(base, mode \\ current())
  def normalize_sync_endpoint(nil, _mode), do: {:error, :missing_endpoint}
  def normalize_sync_endpoint("", _mode), do: {:error, :missing_endpoint}

  def normalize_sync_endpoint(base, mode) when is_binary(base) do
    endpoint = String.trim_trailing(base, "/")

    with :ok <- validate_endpoint_uri(endpoint),
         :ok <- validate_endpoint_host(mode, endpoint) do
      {:ok, endpoint}
    end
  end

  def normalize_sync_endpoint(_base, _mode), do: {:error, :missing_endpoint}

  @doc "Classify whether a base endpoint is acceptable for the selected mode."
  @spec sync_endpoint_allowed?(mode(), String.t()) :: boolean()
  def sync_endpoint_allowed?(mode, base) when is_binary(base) do
    match?({:ok, _}, normalize_sync_endpoint(base, mode))
  end

  def sync_endpoint_allowed?(_mode, _base), do: false

  defp validate_endpoint_uri(endpoint) do
    case URI.parse(endpoint) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        :ok

      _ ->
        {:error, :invalid_endpoint}
    end
  end

  defp validate_endpoint_host(:cloud, endpoint) do
    host = URI.parse(endpoint).host

    if host == @canonical_cloud_host do
      :ok
    else
      {:error, :cloud_endpoint_must_be_controlkeel_com}
    end
  end

  defp validate_endpoint_host(:self_hosted, endpoint) do
    host = URI.parse(endpoint).host

    if host == @canonical_cloud_host do
      {:error, :self_hosted_endpoint_must_not_be_controlkeel_com}
    else
      :ok
    end
  end

  defp validate_endpoint_host(:local, _endpoint), do: :ok

  @doc "Configuration requirements that must be satisfied before remote work runs."
  @spec requirements(mode()) :: [atom()]
  def requirements(:local), do: []
  def requirements(:cloud), do: [:cloud_sync_endpoint, :workspace_identity]
  def requirements(:self_hosted), do: [:cloud_sync_endpoint, :phx_host, :workspace_identity]

  @doc "Return missing requirements for the current process/config environment."
  @spec missing_requirements(mode()) :: [atom()]
  def missing_requirements(mode \\ current()) do
    mode
    |> requirements()
    |> Enum.reject(&requirement_present?/1)
  end

  @doc "True when remote-mode requirements are all present. Local mode is always ready."
  @spec ready?(mode()) :: boolean()
  def ready?(mode \\ current()), do: missing_requirements(mode) == []

  @doc "Diagnostic payload for CLI/doctor/UI surfaces."
  @spec diagnostic(mode()) :: map()
  def diagnostic(mode \\ current()) do
    %{
      mode: mode,
      ready?: ready?(mode),
      missing_requirements: missing_requirements(mode),
      placement: placement_map(mode)
    }
  end

  defp requirement_present?(:cloud_sync_endpoint) do
    present?(Application.get_env(:controlkeel, :cloud_sync_endpoint)) or
      present?(System.get_env("CONTROLKEEL_CLOUD_SYNC_ENDPOINT"))
  end

  defp requirement_present?(:phx_host), do: present?(System.get_env("PHX_HOST"))

  defp requirement_present?(:workspace_identity) do
    match?({:ok, _}, ControlKeel.Cloud.Workspace.Identity.load())
  rescue
    _ -> false
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
