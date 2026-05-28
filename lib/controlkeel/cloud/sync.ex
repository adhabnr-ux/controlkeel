defmodule ControlKeel.Cloud.Sync do
  @moduledoc """
  Bidirectional sync engine for cloud parity.

  Implements append-only event sync for governance records (findings, reviews,
  digests, memories) and optimistic-concurrency sync for editable records
  (sessions, tasks, workspace agents).

  Sync is idempotent by external_id — pushing the same record twice is a no-op.
  Pull upserts by external_id, skipping records that haven't changed.

  Design decisions:
    - Append-only records sync trivially (no conflict semantics)
    - Editable records use lock_version for optimistic concurrency
    - Local keys (Anthropic, OpenAI API keys) NEVER leave the machine
    - Sync is workspace-scoped, not global
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Repo
  alias ControlKeel.Cloud.TelemetryEnvelope

  # ── Push: local → cloud ────────────────────────────────────────────

  @doc """
  Collect unsynced records for a workspace and return them as sync envelopes.
  Does NOT send to cloud — caller handles transport.
  """
  def collect_unsynced(workspace_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

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
        |> Enum.flat_map(fn {kind, schema, _prefix} ->
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
  Serialize a record into a sync envelope for cloud transport.
  """
  def serialize_record({kind, record}) do
    %{
      "external_id" => record.external_id,
      "kind" => kind,
      "payload" => serialize_payload(record),
      "emitted_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "idempotency_key" => TelemetryEnvelope.ulid()
    }
  end

  @doc """
  Mark records as synced after successful push.
  """
  def mark_synced(records) do
    now = DateTime.utc_now()

    Enum.each(records, fn {_kind, record} ->
      record.__struct__.changeset(record, %{synced_at: now})
      |> Repo.update!()
    end)

    :ok
  end

  # ── Pull: cloud → local ────────────────────────────────────────────

  @doc """
  Upsert a batch of records received from cloud.
  Idempotent by external_id — skips if external_id already exists.
  """
  def upsert_batch(envelopes) when is_list(envelopes) do
    results = Enum.map(envelopes, &upsert_single/1)

    %{
      total: length(envelopes),
      inserted: Enum.count(results, &(&1.action == :insert)),
      updated: Enum.count(results, &(&1.action == :update)),
      skipped: Enum.count(results, &(&1.action == :skip)),
      conflicts: Enum.count(results, &(&1.action == :conflict)),
      details: results
    }
  end

  defp upsert_single(%{"external_id" => ext_id, "kind" => kind, "payload" => payload}) do
    schema = kind_to_schema(kind)

    cond do
      is_nil(schema) ->
        %{action: :skip, reason: :unknown_kind, external_id: ext_id}

      is_nil(ext_id) ->
        %{action: :skip, reason: :missing_external_id}

      true ->
        do_upsert(schema, ext_id, kind, payload)
    end
  end

  defp do_upsert(schema, ext_id, kind, payload) do
    existing = Repo.get_by(schema, external_id: ext_id)

    case existing do
      nil ->
        attrs = payload_to_attrs(payload)
        changeset = schema.changeset(struct(schema), Map.put(attrs, :external_id, ext_id))

        case Repo.insert(changeset) do
          {:ok, record} ->
            %{action: :insert, external_id: ext_id, id: record.id}

          {:error, changeset} ->
            %{action: :skip, reason: :insert_failed, external_id: ext_id, errors: format_errors(changeset)}
        end

      existing ->
        if editable?(kind) do
          update_editable(existing, payload)
        else
          if is_nil(existing.synced_at) do
            attrs = payload_to_attrs(payload)
            changeset = schema.changeset(existing, attrs)

            case Repo.update(changeset) do
              {:ok, _} -> %{action: :update, external_id: ext_id}
              {:error, cs} -> %{action: :skip, reason: :update_failed, external_id: ext_id, errors: format_errors(cs)}
            end
          else
            %{action: :skip, reason: :already_synced, external_id: ext_id}
          end
        end
    end
  end

  defp update_editable(existing, payload) do
    cloud_lock = Map.get(payload, "lock_version", 1)

    if cloud_lock <= existing.lock_version do
      %{action: :skip, reason: :stale_version, external_id: existing.external_id}
    else
      attrs =
        payload
        |> payload_to_attrs()
        |> Map.put(:lock_version, existing.lock_version + 1)

      changeset = existing.__struct__.changeset(existing, attrs)

      case Repo.update(changeset) do
        {:ok, _} -> %{action: :update, external_id: existing.external_id}
        {:error, _} -> %{action: :conflict, reason: :lock_version_mismatch, external_id: existing.external_id}
      end
    end
  end

  # ── Schema registry ────────────────────────────────────────────────

  defp append_only_schemas do
    [
      {"finding", ControlKeel.Mission.Finding, "f_"},
      {"review", ControlKeel.Mission.Review, "rev_"},
      {"session_digest", ControlKeel.Mission.SessionDigest, "sd_"},
      {"memory_record", ControlKeel.Memory.Record, "mem_"}
    ]
  end

  defp kind_to_schema("finding"), do: ControlKeel.Mission.Finding
  defp kind_to_schema("review"), do: ControlKeel.Mission.Review
  defp kind_to_schema("session_digest"), do: ControlKeel.Mission.SessionDigest
  defp kind_to_schema("memory_record"), do: ControlKeel.Memory.Record
  defp kind_to_schema("session"), do: ControlKeel.Mission.Session
  defp kind_to_schema("task"), do: ControlKeel.Mission.Task
  defp kind_to_schema("workspace_agent"), do: ControlKeel.Mission.WorkspaceAgent
  defp kind_to_schema(_), do: nil

  defp editable?("session"), do: true
  defp editable?("task"), do: true
  defp editable?("workspace_agent"), do: true
  defp editable?(_), do: false

  # ── Serialization helpers ──────────────────────────────────────────

  defp serialize_payload(record) do
    record
    |> Map.from_struct()
    |> Map.drop([
      :__meta__,
      :__struct__,
      :session,
      :workspace,
      :task,
      :previous_review,
      :revisions,
      :embeddings,
      :proof_bundles,
      :findings,
      :invocations,
      :session_events,
      :task_checkpoints,
      :memory_records,
      :task_edges,
      :task_runs,
      :audit_exports,
      :tasks,
      :reviews
    ])
    |> serialize_map()
  end

  defp serialize_map(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {to_string(k), serialize_value(v)}
    end)
  end

  defp serialize_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp serialize_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp serialize_value(nil), do: nil
  defp serialize_value(v) when is_list(v), do: v
  defp serialize_value(v) when is_map(v), do: serialize_map(v)
  defp serialize_value(v), do: v

  defp payload_to_attrs(payload) when is_map(payload) do
    payload
    |> Enum.flat_map(fn
      {k, v} when is_binary(k) ->
        try do
          [{String.to_existing_atom(k), v}]
        rescue
          ArgumentError -> []
        end

      _ ->
        []
    end)
    |> Map.new()
  end

  defp payload_to_attrs(_), do: %{}

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
