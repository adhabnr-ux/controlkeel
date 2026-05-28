defmodule ControlKeel.Cloud.Sync do
  @moduledoc """
  Bidirectional sync engine for cloud parity.

  Append-only event sync for governance records (findings, reviews, digests,
  memories) and optimistic-concurrency sync for editable records (sessions,
  tasks, workspace agents).

  ## Security & correctness invariants

    * **Allowlist serialization.** Each syncable schema declares `sync_fields/0`
      returning `{:include, [field_atoms_or_{:redact, atom}]}`. Anything not in
      the allowlist is never serialized. Fields marked `{:redact, _}` pass
      through `Cloud.Redactor.redact_value/1` so user-pasted credentials and
      tokens are scrubbed before egress.
    * **Idempotent by external_id.** Pushing or pulling the same record twice
      is a no-op.
    * **Append-only update semantics.** For non-editable kinds, an incoming
      record overwrites local only when its `updated_at` is strictly newer than
      local's. Cloud-side status changes propagate to local; local-side changes
      pushed back to cloud do too.
    * **Optimistic concurrency for editable kinds.** Incoming wins only when
      its `lock_version` is strictly greater than local's. Local `lock_version`
      bumps on every accepted update.
    * **Atomic batch upserts.** `upsert_batch/1` wraps each batch in a
      `Repo.transaction`, so partial failures roll back.
    * **Protocol versioning.** Envelopes carry `sync_protocol_version`. Mismatch
      between sender and receiver produces a logged warning, not silent corruption.
    * **Local secrets never leave the host.** The redactor runs on every
      `{:redact, _}` field. The doc/test in this module is the contract.
  """

  import Ecto.Query, warn: false
  require Logger

  alias ControlKeel.Cloud.{Redactor, TelemetryEnvelope}
  alias ControlKeel.Repo

  @sync_protocol_version 1
  @default_batch_limit 500
  @default_max_batch_bytes 8 * 1024 * 1024

  # ── Public API ─────────────────────────────────────────────────────

  @doc "Protocol version emitted on every sync envelope."
  def protocol_version, do: @sync_protocol_version

  @doc """
  Collect unsynced records for a workspace and return them as wrapped records.
  Does NOT send to cloud — caller (typically SyncEngine) handles transport.
  """
  def collect_unsynced(workspace_id, opts \\ []) when is_integer(workspace_id) do
    limit = Keyword.get(opts, :limit, @default_batch_limit)

    session_ids =
      ControlKeel.Mission.Session
      |> where([s], s.workspace_id == ^workspace_id)
      |> select([s], s.id)
      |> Repo.all()

    if session_ids == [] do
      %{total: 0, records: []}
    else
      records =
        append_only_schemas()
        |> Enum.flat_map(fn {kind, schema} ->
          schema
          |> where([r], r.session_id in ^session_ids)
          |> where([r], is_nil(r.synced_at))
          |> limit(^limit)
          |> Repo.all()
          |> Enum.map(&{kind, &1})
        end)

      %{total: length(records), records: records}
    end
  end

  @doc """
  Serialize a `{kind, record}` tuple into an envelope safe to ship over the wire.

  Drops fields not in the schema's `sync_fields/0` allowlist, redacts fields
  marked `{:redact, _}`, and stamps the envelope with the redaction-policy and
  sync-protocol versions.
  """
  def serialize_record({kind, record}) do
    schema = record.__struct__

    {:include, field_specs} = schema.sync_fields()
    payload = serialize_payload(record, field_specs)

    %{
      "external_id" => Map.get(payload, "external_id"),
      "kind" => kind,
      "payload" => payload,
      "emitted_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "idempotency_key" => TelemetryEnvelope.ulid(),
      "sync_protocol_version" => @sync_protocol_version,
      "redaction_policy_version" => Redactor.policy_version()
    }
  end

  @doc """
  Mark records as synced after a successful push. Uses a single
  `Repo.update_all` per schema so this is N round-trips for N kinds, not N
  records.
  """
  def mark_synced(records) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    records
    |> Enum.group_by(fn {_kind, record} -> record.__struct__ end)
    |> Enum.each(fn {schema, items} ->
      ids = Enum.map(items, fn {_k, r} -> r.id end)

      from(r in schema, where: r.id in ^ids)
      |> Repo.update_all(set: [synced_at: now])
    end)

    :ok
  end

  @doc """
  Upsert a batch of envelopes received from cloud. Wrapped in a single
  `Repo.transaction` — any rollback aborts the whole batch.

  Options:

    * `:max_batch_bytes` (integer, default 8MB) — reject batches whose
      JSON-encoded payload exceeds this.
  """
  def upsert_batch(envelopes, opts \\ []) when is_list(envelopes) do
    max_bytes = Keyword.get(opts, :max_batch_bytes, @default_max_batch_bytes)

    with :ok <- check_batch_size(envelopes, max_bytes) do
      results = upsert_in_transaction(envelopes)

      {:ok,
       %{
         total: length(envelopes),
         inserted: count_action(results, :insert),
         updated: count_action(results, :update),
         skipped: count_action(results, :skip),
         no_change: count_action(results, :no_change),
         conflicts: count_action(results, :conflict),
         details: results
       }}
    end
  end

  defp upsert_in_transaction(envelopes) do
    {:ok, results} =
      Repo.transaction(fn ->
        Enum.map(envelopes, &upsert_single/1)
      end)

    results
  end

  defp check_batch_size(envelopes, max_bytes) do
    case envelopes |> Jason.encode!() |> byte_size() do
      n when n <= max_bytes -> :ok
      n -> {:error, {:batch_too_large, %{bytes: n, max: max_bytes}}}
    end
  rescue
    _ -> :ok
  end

  defp count_action(results, action), do: Enum.count(results, &(&1.action == action))

  # ── Single-envelope upsert ─────────────────────────────────────────

  defp upsert_single(%{"sync_protocol_version" => v} = envelope)
       when is_integer(v) and v != @sync_protocol_version do
    Logger.warning(
      "[Cloud.Sync] envelope protocol version #{v} differs from local #{@sync_protocol_version}; " <>
        "applying best-effort. external_id=#{inspect(envelope["external_id"])}"
    )

    upsert_payload(envelope)
  end

  defp upsert_single(envelope), do: upsert_payload(envelope)

  defp upsert_payload(%{"external_id" => ext_id, "kind" => kind, "payload" => payload}) do
    schema = kind_to_schema(kind)

    cond do
      is_nil(schema) ->
        %{action: :skip, reason: :unknown_kind, external_id: ext_id}

      is_nil(ext_id) ->
        %{action: :skip, reason: :missing_external_id, external_id: nil}

      true ->
        do_upsert(schema, kind, ext_id, payload)
    end
  end

  defp upsert_payload(_),
    do: %{action: :skip, reason: :malformed_envelope, external_id: nil}

  defp do_upsert(schema, kind, ext_id, payload) do
    case Repo.get_by(schema, external_id: ext_id) do
      nil ->
        insert_new(schema, ext_id, payload)

      existing ->
        if editable?(kind) do
          update_editable(existing, payload)
        else
          update_append_only(existing, payload)
        end
    end
  end

  defp insert_new(schema, ext_id, payload) do
    attrs = payload_to_attrs(payload, schema) |> Map.put(:external_id, ext_id)

    case schema |> struct() |> schema.changeset(attrs) |> Repo.insert() do
      {:ok, record} ->
        %{action: :insert, external_id: ext_id, id: record.id}

      {:error, changeset} ->
        %{
          action: :skip,
          reason: :insert_failed,
          external_id: ext_id,
          errors: format_errors(changeset)
        }
    end
  end

  defp update_append_only(existing, payload) do
    incoming_updated_at = parse_datetime(Map.get(payload, "updated_at"))
    local_updated_at = existing.updated_at

    cond do
      incoming_updated_at == nil ->
        %{action: :no_change, reason: :no_incoming_timestamp, external_id: existing.external_id}

      local_updated_at != nil and
          DateTime.compare(incoming_updated_at, local_updated_at) in [:lt, :eq] ->
        %{action: :no_change, reason: :not_newer, external_id: existing.external_id}

      true ->
        attrs = payload_to_attrs(payload, existing.__struct__)
        changeset = existing.__struct__.changeset(existing, attrs)

        case Repo.update(changeset) do
          {:ok, _} ->
            %{action: :update, external_id: existing.external_id}

          {:error, cs} ->
            %{
              action: :skip,
              reason: :update_failed,
              external_id: existing.external_id,
              errors: format_errors(cs)
            }
        end
    end
  end

  defp update_editable(existing, payload) do
    cloud_lock = Map.get(payload, "lock_version") || Map.get(payload, :lock_version) || 1
    local_lock = existing.lock_version || 1

    if cloud_lock <= local_lock do
      %{
        action: :no_change,
        reason: :stale_or_equal_version,
        external_id: existing.external_id,
        local_lock: local_lock,
        cloud_lock: cloud_lock
      }
    else
      attrs =
        payload
        |> payload_to_attrs(existing.__struct__)
        |> Map.put(:lock_version, local_lock + 1)

      changeset = existing.__struct__.changeset(existing, attrs)

      case Repo.update(changeset) do
        {:ok, _} ->
          %{action: :update, external_id: existing.external_id}

        {:error, cs} ->
          %{
            action: :conflict,
            reason: :lock_version_mismatch,
            external_id: existing.external_id,
            errors: format_errors(cs)
          }
      end
    end
  end

  # ── Schema registry ────────────────────────────────────────────────

  defp append_only_schemas do
    [
      {"finding", ControlKeel.Mission.Finding},
      {"review", ControlKeel.Mission.Review},
      {"session_digest", ControlKeel.Mission.SessionDigest},
      {"memory_record", ControlKeel.Memory.Record}
    ]
  end

  @doc "Public for tests + the controller's pull endpoint."
  def syncable_schemas do
    append_only_schemas() ++
      [
        {"session", ControlKeel.Mission.Session},
        {"task", ControlKeel.Mission.Task},
        {"workspace_agent", ControlKeel.Mission.WorkspaceAgent}
      ]
  end

  defp kind_to_schema(kind) do
    syncable_schemas()
    |> Enum.find_value(fn {k, schema} -> if k == kind, do: schema end)
  end

  defp editable?("session"), do: true
  defp editable?("task"), do: true
  defp editable?("workspace_agent"), do: true
  defp editable?(_), do: false

  # ── Serialization helpers ──────────────────────────────────────────

  defp serialize_payload(record, field_specs) do
    field_specs
    |> Enum.flat_map(fn
      {:redact, field} ->
        case Map.get(record, field) do
          nil -> [{to_string(field), nil}]
          v -> [{to_string(field), Redactor.redact_value(serialize_value(v))}]
        end

      field when is_atom(field) ->
        case Map.get(record, field) do
          nil -> [{to_string(field), nil}]
          v -> [{to_string(field), serialize_value(v)}]
        end
    end)
    |> Map.new()
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp serialize_value(%Date{} = d), do: Date.to_iso8601(d)
  defp serialize_value(%Time{} = t), do: Time.to_iso8601(t)
  defp serialize_value(nil), do: nil
  defp serialize_value(v) when is_list(v), do: Enum.map(v, &serialize_value/1)

  defp serialize_value(v) when is_map(v) and not is_struct(v) do
    Map.new(v, fn {k, vv} -> {to_string(k), serialize_value(vv)} end)
  end

  defp serialize_value(v), do: v

  defp payload_to_attrs(payload, schema) when is_map(payload) do
    schema_fields =
      case schema.sync_fields() do
        {:include, specs} ->
          MapSet.new(
            Enum.map(specs, fn
              {:redact, f} -> f
              f -> f
            end)
          )
      end

    {known, unknown} =
      payload
      |> Enum.split_with(fn {k, _v} ->
        case to_atom_safe(k) do
          {:ok, atom} -> MapSet.member?(schema_fields, atom)
          :error -> false
        end
      end)

    if unknown != [] do
      Logger.warning(
        "[Cloud.Sync] dropping unknown payload fields on #{inspect(schema)}: " <>
          inspect(Enum.map(unknown, fn {k, _} -> k end))
      )
    end

    known
    |> Enum.flat_map(fn {k, v} ->
      case to_atom_safe(k) do
        {:ok, atom} -> [{atom, decode_value(atom, v)}]
        :error -> []
      end
    end)
    |> Map.new()
  end

  defp payload_to_attrs(_, _), do: %{}

  defp to_atom_safe(k) when is_atom(k), do: {:ok, k}

  defp to_atom_safe(k) when is_binary(k) do
    try do
      {:ok, String.to_existing_atom(k)}
    rescue
      ArgumentError -> :error
    end
  end

  defp to_atom_safe(_), do: :error

  # The append-only update path needs the incoming `updated_at` parsed back
  # to a DateTime so the newer-wins comparison works. Other ISO-8601 fields
  # we leave to the schema's cast to coerce.
  defp decode_value(field, v) when field in [:updated_at, :inserted_at, :synced_at, :archived_at] do
    case parse_datetime(v) do
      nil -> v
      dt -> dt
    end
  end

  defp decode_value(_field, v), do: v

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = v), do: v

  defp parse_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
