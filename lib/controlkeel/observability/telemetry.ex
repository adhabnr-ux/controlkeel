defmodule ControlKeel.Observability.Telemetry do
  @moduledoc false

  alias ControlKeel.Observability
  alias ControlKeel.Observability.ImportedEnvelope
  alias ControlKeel.Repo

  @schema_version "controlkeel.observability.v1"
  @required_keys ~w(schema_version exported_at source session_run problems redaction integrity)
  @fingerprint_algorithm "sha256"

  def schema_version, do: @schema_version

  def export_session(session_id, opts \\ []) do
    with {:ok, run} <- Observability.session_run(session_id) do
      problems =
        run.session.workspace_id
        |> problems_opts(opts)
        |> Observability.problems()

      {:ok, envelope(run, problems, opts)}
    end
  end

  def import_preview(path, opts \\ []) when is_binary(path) do
    with true <- Keyword.get(opts, :dry_run, false) || {:error, :dry_run_required},
         {:ok, payload} <- read_envelope(path) do
      {:ok, preview(payload)}
    else
      error ->
        error
    end
  end

  def import_persist(path, opts \\ []) when is_binary(path) do
    with {:ok, payload} <- read_envelope(path),
         preview <- preview(payload),
         :ok <- ensure_verified(preview),
         {:ok, result} <- persist_payload(payload, preview, opts) do
      {:ok, result}
    end
  end

  def validate_envelope(payload) when is_map(payload) do
    missing = Enum.reject(@required_keys, &Map.has_key?(payload, &1))

    cond do
      missing != [] ->
        {:error, {:missing_keys, missing}}

      payload["schema_version"] != @schema_version ->
        {:error, {:unsupported_schema_version, payload["schema_version"]}}

      not is_map(payload["session_run"]) ->
        {:error, {:invalid_field, "session_run"}}

      not is_map(payload["problems"]) ->
        {:error, {:invalid_field, "problems"}}

      true ->
        :ok
    end
  end

  def validate_envelope(_payload), do: {:error, :invalid_envelope}

  defp read_envelope(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, payload} <- Jason.decode(contents),
         :ok <- validate_envelope(payload) do
      {:ok, payload}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error, {:invalid_json, Exception.message(error)}}

      error ->
        error
    end
  end

  defp envelope(run, problems, opts) do
    exported_at =
      opts
      |> Keyword.get(:exported_at, DateTime.utc_now())
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    base = %{
      schema_version: @schema_version,
      exported_at: exported_at,
      source: %{
        product: "controlkeel",
        surface: "cli",
        mode: "local_first_observability_export"
      },
      session_run: run,
      problems: problems,
      redaction: %{
        policy: "summary_only",
        raw_context_bodies: false,
        raw_memory_bodies: false,
        raw_tool_inputs: false,
        note:
          "Envelope uses observability summaries; raw context, memory bodies, secrets, and tool input payloads are not exported by default."
      }
    }

    Map.put(base, :integrity, integrity(base, run, problems))
  end

  defp problems_opts(workspace_id, opts) do
    opts
    |> Keyword.get(:problems_opts, [])
    |> Keyword.put_new(:workspace_id, workspace_id)
  end

  defp integrity(base, run, problems) do
    %{
      session_id: run.session.id,
      health: run.health.status,
      timeline_events: run.timeline.count,
      active_findings: run.findings.active,
      problem_groups: problems.count,
      total_problem_findings: problems.total_findings,
      import_mutation_allowed: false,
      fingerprint_algorithm: @fingerprint_algorithm,
      payload_sha256: fingerprint(base)
    }
  end

  defp preview(payload) do
    session_run = payload["session_run"]
    session = Map.get(session_run, "session", %{})
    health = Map.get(session_run, "health", %{})
    problems = payload["problems"]
    integrity = payload["integrity"]

    %{
      schema_version: payload["schema_version"],
      exported_at: payload["exported_at"],
      dry_run: true,
      mutation: "none",
      session_id: Map.get(session, "id") || Map.get(integrity, "session_id"),
      session_title: Map.get(session, "title"),
      health: Map.get(health, "status") || Map.get(integrity, "health"),
      problem_groups: Map.get(problems, "count") || Map.get(integrity, "problem_groups") || 0,
      total_problem_findings:
        Map.get(problems, "total_findings") || Map.get(integrity, "total_problem_findings") || 0,
      redaction_policy: get_in(payload, ["redaction", "policy"]),
      integrity_status: integrity_status(payload),
      payload_sha256: Map.get(integrity, "payload_sha256")
    }
  end

  defp ensure_verified(%{integrity_status: "verified"}), do: :ok

  defp ensure_verified(%{integrity_status: status}),
    do: {:error, {:integrity_not_verified, status}}

  defp persist_payload(payload, preview, opts) do
    case Repo.get_by(ImportedEnvelope, payload_sha256: preview.payload_sha256) do
      %ImportedEnvelope{} = existing ->
        {:ok, import_result(existing, "duplicate")}

      nil ->
        %ImportedEnvelope{}
        |> ImportedEnvelope.changeset(import_attrs(payload, preview, opts))
        |> Repo.insert()
        |> case do
          {:ok, record} -> {:ok, import_result(record, "stored")}
          error -> error
        end
    end
  end

  defp import_attrs(payload, preview, opts) do
    %{
      schema_version: preview.schema_version,
      exported_at: parse_datetime(preview.exported_at),
      source: Map.get(payload, "source", %{}),
      original_session_id: preview.session_id,
      original_session_title: preview.session_title,
      health: preview.health,
      problem_groups: preview.problem_groups,
      total_problem_findings: preview.total_problem_findings,
      redaction_policy: preview.redaction_policy,
      integrity_status: preview.integrity_status,
      payload_sha256: preview.payload_sha256,
      import_mode: "local_persist",
      imported_at:
        Keyword.get(opts, :imported_at, DateTime.utc_now()) |> DateTime.truncate(:second),
      envelope: payload,
      workspace_id: Keyword.get(opts, :workspace_id),
      session_id: Keyword.get(opts, :session_id)
    }
  end

  defp import_result(%ImportedEnvelope{} = record, status) do
    %{
      status: status,
      id: record.id,
      schema_version: record.schema_version,
      exported_at: datetime_to_iso8601(record.exported_at),
      imported_at: datetime_to_iso8601(record.imported_at),
      import_mode: record.import_mode,
      session_id: record.original_session_id,
      session_title: record.original_session_title,
      health: record.health,
      problem_groups: record.problem_groups,
      total_problem_findings: record.total_problem_findings,
      redaction_policy: record.redaction_policy,
      integrity_status: record.integrity_status,
      payload_sha256: record.payload_sha256,
      mutation: "none"
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :second)
      _other -> nil
    end
  end

  defp datetime_to_iso8601(nil), do: nil
  defp datetime_to_iso8601(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)

  defp integrity_status(payload) do
    expected = get_in(payload, ["integrity", "payload_sha256"])

    cond do
      not is_binary(expected) or expected == "" ->
        "missing"

      expected == fingerprint(Map.drop(payload, ["integrity"])) ->
        "verified"

      true ->
        "mismatch"
    end
  end

  defp fingerprint(payload) do
    payload
    |> canonical_term()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), canonical_term(item)} end)
    |> Enum.sort_by(fn {key, _item} -> key end)
  end

  defp canonical_term(value) when is_list(value), do: Enum.map(value, &canonical_term/1)
  defp canonical_term(value), do: value
end
