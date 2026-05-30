defmodule ControlKeel.Cloud.TelemetryEnvelope do
  @moduledoc """
  Build a D3 telemetry envelope for one governance event.

  Envelope shape (per the
  [cloud roadmap D3 decision](../../docs/cloud-enterprise-roadmap.md)):

      %{
        "schema_version" => "1",
        "event_id" => "<ULID>",
        "workspace_id" => "ws_...",
        "emitted_at" => "<ISO8601>",
        "kind" => "finding.created",
        "redaction_policy_version" => "2026.05",
        "idempotency_key" => "<ULID>",   # defaults to event_id
        "payload" => %{...}              # redacted, kind-specific
      }

  Build is pure: no network egress, no DB writes. Use this module to construct
  envelopes that downstream slices will batch and send.

  Build fails closed when:

    - cloud telemetry is `:disabled`
    - the kind is not a recognised governance event
    - the payload fails redaction
  """

  alias ControlKeel.Cloud.Redactor
  alias ControlKeel.Cloud.TelemetryConfig

  @schema_version "1"
  @recognised_kinds ~w(
    finding.created
    finding.approved
    finding.rejected
    review.submitted
    review.approved
    review.denied
    proof.generated
    task.completed
    task.failed
    budget.exceeded
    install.success
    attach.success
    heartbeat
  )

  @typedoc "Build error reasons."
  @type build_error ::
          :telemetry_disabled
          | :workspace_not_set
          | {:unknown_kind, String.t()}
          | {:redaction_failed, term()}

  @doc "All event kinds the envelope builder will accept."
  @spec recognised_kinds() :: [String.t()]
  def recognised_kinds, do: @recognised_kinds

  @doc """
  Build a telemetry envelope.

  Reads telemetry state via `TelemetryConfig.load/0`. Fails closed when sync is
  not opted in or when redaction rejects the payload.

  Options:

    - `:idempotency_key` — explicit override; defaults to `event_id`
    - `:state` — pre-loaded telemetry state (for tests and batching call sites
      that want to avoid re-reading the config file per event)
    - `:emitted_at` — override timestamp (defaults to `DateTime.utc_now/0`)
  """
  @spec build(String.t(), map(), keyword()) :: {:ok, map()} | {:error, build_error()}
  def build(kind, payload, opts \\ []) when is_binary(kind) and is_map(payload) do
    state = Keyword.get(opts, :state) || TelemetryConfig.load()

    with :ok <- ensure_enabled(state),
         :ok <- ensure_workspace(state),
         :ok <- ensure_known_kind(kind),
         {:ok, redacted, policy_version} <- redact_payload(payload) do
      event_id = ulid()
      idempotency_key = Keyword.get(opts, :idempotency_key, event_id)

      emitted_at =
        Keyword.get(opts, :emitted_at, DateTime.utc_now())
        |> DateTime.truncate(:second)
        |> DateTime.to_iso8601()

      {:ok,
       %{
         "schema_version" => @schema_version,
         "event_id" => event_id,
         "workspace_id" => state.workspace_id,
         "emitted_at" => emitted_at,
         "kind" => kind,
         "redaction_policy_version" => policy_version,
         "idempotency_key" => idempotency_key,
         "payload" => redacted
       }}
    end
  end

  defp ensure_enabled(state) do
    if TelemetryConfig.enabled?(state), do: :ok, else: {:error, :telemetry_disabled}
  end

  defp ensure_workspace(%{workspace_id: nil}), do: {:error, :workspace_not_set}
  defp ensure_workspace(%{workspace_id: ws}) when is_binary(ws), do: :ok
  defp ensure_workspace(_), do: {:error, :workspace_not_set}

  defp ensure_known_kind(kind) do
    if kind in @recognised_kinds, do: :ok, else: {:error, {:unknown_kind, kind}}
  end

  defp redact_payload(payload) do
    case Redactor.redact(payload) do
      {:ok, redacted, version} -> {:ok, redacted, version}
      {:error, reason} -> {:error, {:redaction_failed, reason}}
    end
  end

  # Crockford base32 alphabet — excludes I, L, O, U to avoid ambiguity
  @crockford ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  @doc """
  Generate a ULID (Universally Unique Lexicographically Sortable Identifier).

  48-bit millisecond timestamp + 80-bit randomness, Crockford-base32 encoded
  into 26 characters. Lexicographic order matches time order.
  """
  @spec ulid() :: String.t()
  def ulid do
    ts_ms = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(10)

    <<ts::unsigned-big-integer-size(48), rand::unsigned-big-integer-size(80)>> =
      <<ts_ms::unsigned-big-integer-size(48), random::binary>>

    encode_crockford(ts, 10) <> encode_crockford(rand, 16)
  end

  defp encode_crockford(value, length) do
    Stream.unfold({value, length}, fn
      {_v, 0} -> nil
      {v, n} -> {Enum.at(@crockford, rem(v, 32)), {div(v, 32), n - 1}}
    end)
    |> Enum.to_list()
    |> Enum.reverse()
    |> List.to_string()
  end
end
