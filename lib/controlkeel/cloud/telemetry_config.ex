defmodule ControlKeel.Cloud.TelemetryConfig do
  @moduledoc """
  Local state for opt-in cloud telemetry sync.

  Telemetry is disabled by default. State lives in a plain JSON file under
  `ControlKeel.Runtime.Paths.config_dir/0` so it survives package reinstalls and
  is human-inspectable. No code path mutates this file as a side effect — the
  user must explicitly opt in via `controlkeel telemetry enable` (Phase 2,
  upcoming slice).

  This module is read-only in this slice. Write operations are intentionally
  deferred so the schema can stabilize through review before any mutation API
  ships.

  ## Levels

  Strictly increasing, cumulative. Each level includes everything below it.

    - `:disabled` (default) — nothing leaves the local node
    - `:health` — heartbeat, version, install/attach success
    - `:governance` — finding counts/severity, approval state, budget summaries
    - `:evidence` — proof bundles, validation summaries, trace packets
    - `:full_audit` — complete session transcripts (redacted), policy history

  See [docs/cloud-enterprise-roadmap.md](../../docs/cloud-enterprise-roadmap.md)
  "Opt-in telemetry levels" for the full contract.
  """

  alias ControlKeel.Cloud.WorkspaceIdentity
  alias ControlKeel.Runtime.Paths

  @filename "cloud-telemetry.json"
  @schema_version "1"
  @default_redaction_policy_version "2026.05"
  @file_mode 0o600
  @levels [:disabled, :health, :governance, :evidence, :full_audit]
  @opt_in_levels [:health, :governance, :evidence, :full_audit]

  @typedoc "Telemetry sync state."
  @type state :: %{
          level: atom(),
          enabled_at: DateTime.t() | nil,
          workspace_id: String.t() | nil,
          redaction_policy_version: String.t(),
          schema_version: String.t(),
          source: :default | :file,
          path: String.t(),
          load_error: String.t() | nil
        }

  @doc "All recognised telemetry levels, lowest to highest."
  @spec levels() :: [atom()]
  def levels, do: @levels

  @doc "Levels that count as opt-in (everything above `:disabled`)."
  @spec opt_in_levels() :: [atom()]
  def opt_in_levels, do: @opt_in_levels

  @doc "Coerce a string or atom into a known level, or `:error`."
  @spec parse_level(String.t() | atom()) :: {:ok, atom()} | :error
  def parse_level(value) when is_atom(value) do
    if value in @levels, do: {:ok, value}, else: :error
  end

  def parse_level(value) when is_binary(value) do
    atom = String.to_existing_atom(value)
    if atom in @levels, do: {:ok, atom}, else: :error
  rescue
    ArgumentError -> :error
  end

  def parse_level(_), do: :error

  @doc """
  Enable telemetry sync at a specific opt-in level.

  Requires a workspace identity to exist (created via `controlkeel cloud connect`).
  Returns `{:error, :not_connected}` when no workspace identity is present so a
  user cannot opt in to remote sync before they have a stable identity.

  `:disabled` is rejected here — use `disable/0` instead, which is more obvious
  at call sites.
  """
  @spec enable(atom()) ::
          {:ok, state()}
          | {:error, :invalid_level | :not_connected | {:write_failed, term()}}
  def enable(level) when level in @opt_in_levels do
    case WorkspaceIdentity.load() do
      {:ok, identity} ->
        write(%{
          level: level,
          workspace_id: identity.workspace_id,
          enabled_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:error, :not_connected} ->
        {:error, :not_connected}

      {:error, _reason} ->
        {:error, :not_connected}
    end
  end

  def enable(_), do: {:error, :invalid_level}

  @doc """
  Disable telemetry sync. Writes the disabled state to disk so the user's
  intent is durable and visible to the doctor.

  Workspace identity is preserved — disable is not the same as
  disconnect.
  """
  @spec disable() :: {:ok, state()} | {:error, {:write_failed, term()}}
  def disable do
    write(%{level: :disabled, workspace_id: nil, enabled_at: nil})
  end

  defp write(attrs) do
    file_path = path()

    body =
      Jason.encode!(%{
        "level" => Atom.to_string(attrs.level),
        "enabled_at" => attrs.enabled_at && DateTime.to_iso8601(attrs.enabled_at),
        "workspace_id" => attrs.workspace_id,
        "redaction_policy_version" => @default_redaction_policy_version,
        "schema_version" => @schema_version
      })

    with :ok <- File.mkdir_p(Path.dirname(file_path)),
         :ok <- File.write(file_path, body),
         :ok <- chmod_secure(file_path) do
      {:ok, load()}
    else
      {:error, reason} -> {:error, {:write_failed, reason}}
    end
  end

  defp chmod_secure(file_path) do
    case File.chmod(file_path, @file_mode) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end

  @doc "Absolute path to the telemetry config file (does not create it)."
  @spec path() :: String.t()
  def path, do: Path.join(Paths.config_dir(), @filename)

  @doc """
  Load current telemetry state.

  Returns the default disabled state when the file is missing. Returns
  `:disabled` with a populated `load_error` when the file is unreadable or
  malformed, so a broken config never silently enables sync.
  """
  @spec load() :: state()
  def load do
    file_path = path()

    case File.read(file_path) do
      {:error, :enoent} ->
        default_state(file_path)

      {:error, reason} ->
        default_state(file_path)
        |> Map.put(:load_error, "could not read #{file_path}: #{inspect(reason)}")

      {:ok, body} ->
        parse(body, file_path)
    end
  end

  @doc "True when telemetry sync is opted in to any level above `:disabled`."
  @spec enabled?(state()) :: boolean()
  def enabled?(%{level: :disabled}), do: false
  def enabled?(%{level: level}) when level in @levels, do: true
  def enabled?(_), do: false

  @doc "Human-readable summary suitable for CLI output."
  @spec summary(state()) :: String.t()
  def summary(%{level: :disabled, load_error: nil}), do: "disabled (opt-in not yet configured)"

  def summary(%{level: :disabled, load_error: error}) when is_binary(error),
    do: "disabled (config load error: #{error})"

  def summary(%{level: level, enabled_at: enabled_at, workspace_id: ws}) do
    parts = ["level=#{level}"]
    parts = if ws, do: parts ++ ["workspace=#{ws}"], else: parts

    parts =
      if enabled_at do
        parts ++ ["enabled_at=#{DateTime.to_iso8601(enabled_at)}"]
      else
        parts
      end

    Enum.join(parts, " ")
  end

  defp default_state(file_path) do
    %{
      level: :disabled,
      enabled_at: nil,
      workspace_id: nil,
      redaction_policy_version: @default_redaction_policy_version,
      schema_version: @schema_version,
      source: :default,
      path: file_path,
      load_error: nil
    }
  end

  defp parse(body, file_path) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) ->
        decode_state(map, file_path)

      {:ok, _} ->
        default_state(file_path)
        |> Map.put(:load_error, "telemetry config is not a JSON object")

      {:error, reason} ->
        default_state(file_path)
        |> Map.put(:load_error, "JSON parse error: #{Exception.message(reason)}")
    end
  end

  defp decode_state(map, file_path) do
    level = decode_level(Map.get(map, "level"))

    state = %{
      level: level,
      enabled_at: decode_datetime(Map.get(map, "enabled_at")),
      workspace_id: presence(Map.get(map, "workspace_id")),
      redaction_policy_version:
        presence(Map.get(map, "redaction_policy_version")) || @default_redaction_policy_version,
      schema_version: presence(Map.get(map, "schema_version")) || @schema_version,
      source: :file,
      path: file_path,
      load_error: nil
    }

    case level do
      :unknown ->
        Map.merge(state, %{
          level: :disabled,
          load_error: "unknown level value: #{inspect(Map.get(map, "level"))}"
        })

      _ ->
        state
    end
  end

  defp decode_level(value) when is_binary(value) do
    atom = String.to_existing_atom(value)
    if atom in @levels, do: atom, else: :unknown
  rescue
    ArgumentError -> :unknown
  end

  defp decode_level(_), do: :unknown

  defp decode_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp decode_datetime(_), do: nil

  defp presence(""), do: nil
  defp presence(value), do: value
end
