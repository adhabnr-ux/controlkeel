defmodule ControlKeel.Cloud.Ingestion do
  @moduledoc """
  Server-side ingestion for cloud telemetry batches.

  Accepts a parsed JSON batch posted to `POST /cloud/v1/telemetry`, validates
  it against the D3 schema, and persists each envelope to
  `ControlKeel.Cloud.ReceivedTelemetryEvent`. Idempotent at the storage layer
  via unique indexes on `event_id` and `idempotency_key`.

  This module does not include the HTTP/controller plumbing — that lives in
  `ControlKeelWeb.CloudTelemetryController`. Separating the validation/persist
  concern from the controller lets tests target the rules directly without
  spinning up the endpoint.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.ReceivedTelemetryEvent
  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Repo

  @schema_version "1"
  @required_keys ~w(schema_version workspace_id events)

  @typedoc "Per-event outcome inside an accepted batch."
  @type event_outcome :: %{
          event_id: String.t(),
          status: :accepted | :duplicate | :rejected,
          reason: String.t() | nil
        }

  @typedoc "Result of ingest/2."
  @type result ::
          {:ok,
           %{
             accepted: non_neg_integer(),
             duplicates: non_neg_integer(),
             rejected: non_neg_integer(),
             outcomes: [event_outcome()]
           }}
          | {:error,
             :malformed_batch
             | :unsupported_schema_version
             | :workspace_mismatch
             | :empty_batch
             | :batch_too_large}

  @max_batch_size 500

  @doc """
  Ingest a parsed batch.

  `auth_workspace_id` is the workspace ID derived from the request
  authorization header. Each envelope's `workspace_id` must match — otherwise
  the whole batch is rejected to prevent one workspace from forging events for
  another.
  """
  @spec ingest(map(), String.t()) :: result()
  def ingest(batch, auth_workspace_id) when is_map(batch) and is_binary(auth_workspace_id) do
    with :ok <- validate_required_keys(batch),
         :ok <- validate_schema_version(batch),
         :ok <- validate_workspace(batch, auth_workspace_id),
         :ok <- validate_events_list(batch) do
      events = batch["events"]
      outcomes = Enum.map(events, &persist_event(&1, auth_workspace_id))

      summary = summarize(outcomes)
      {:ok, summary}
    end
  end

  def ingest(_, _), do: {:error, :malformed_batch}

  defp validate_required_keys(batch) do
    if Enum.all?(@required_keys, &Map.has_key?(batch, &1)) do
      :ok
    else
      {:error, :malformed_batch}
    end
  end

  defp validate_schema_version(%{"schema_version" => @schema_version}), do: :ok
  defp validate_schema_version(_), do: {:error, :unsupported_schema_version}

  defp validate_workspace(%{"workspace_id" => ws}, auth_ws) when ws == auth_ws, do: :ok
  defp validate_workspace(_, _), do: {:error, :workspace_mismatch}

  defp validate_events_list(%{"events" => events}) when is_list(events) do
    cond do
      events == [] -> {:error, :empty_batch}
      length(events) > @max_batch_size -> {:error, :batch_too_large}
      true -> :ok
    end
  end

  defp validate_events_list(_), do: {:error, :malformed_batch}

  defp persist_event(envelope, source_workspace_id) when is_map(envelope) do
    case validate_envelope(envelope, source_workspace_id) do
      :ok ->
        do_persist(envelope, source_workspace_id)

      {:error, reason} ->
        %{event_id: Map.get(envelope, "event_id"), status: :rejected, reason: reason}
    end
  end

  defp persist_event(_, _),
    do: %{event_id: nil, status: :rejected, reason: "envelope is not a JSON object"}

  defp validate_envelope(envelope, source_workspace_id) do
    required =
      ~w(schema_version event_id workspace_id emitted_at kind redaction_policy_version idempotency_key payload)

    missing = Enum.reject(required, &Map.has_key?(envelope, &1))

    cond do
      missing != [] ->
        {:error, "missing fields: #{Enum.join(missing, ", ")}"}

      Map.get(envelope, "schema_version") != @schema_version ->
        {:error, "envelope schema_version mismatch"}

      Map.get(envelope, "workspace_id") != source_workspace_id ->
        {:error, "envelope workspace_id mismatch"}

      Map.get(envelope, "kind") not in TelemetryEnvelope.recognised_kinds() ->
        {:error, "unknown kind: #{inspect(Map.get(envelope, "kind"))}"}

      true ->
        :ok
    end
  end

  defp do_persist(envelope, source_workspace_id) do
    event_id = envelope["event_id"]

    case Repo.get_by(ReceivedTelemetryEvent, event_id: event_id) do
      nil ->
        attrs = envelope_to_attrs(envelope, source_workspace_id)

        case %ReceivedTelemetryEvent{}
             |> ReceivedTelemetryEvent.changeset(attrs)
             |> Repo.insert() do
          {:ok, _event} ->
            %{event_id: event_id, status: :accepted, reason: nil}

          {:error, %Ecto.Changeset{errors: errors}} ->
            cond do
              Keyword.has_key?(errors, :event_id) ->
                %{event_id: event_id, status: :duplicate, reason: nil}

              Keyword.has_key?(errors, :idempotency_key) ->
                %{event_id: event_id, status: :duplicate, reason: nil}

              true ->
                %{event_id: event_id, status: :rejected, reason: inspect(errors)}
            end
        end

      _existing ->
        %{event_id: event_id, status: :duplicate, reason: nil}
    end
  end

  defp envelope_to_attrs(envelope, source_workspace_id) do
    %{
      event_id: envelope["event_id"],
      workspace_id: envelope["workspace_id"],
      kind: envelope["kind"],
      emitted_at: parse_iso(envelope["emitted_at"]),
      received_at: DateTime.utc_now() |> DateTime.truncate(:second),
      idempotency_key: envelope["idempotency_key"],
      redaction_policy_version: envelope["redaction_policy_version"],
      schema_version: envelope["schema_version"],
      body: Jason.encode!(envelope),
      source_workspace_id: source_workspace_id
    }
  end

  defp parse_iso(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp parse_iso(_), do: nil

  defp summarize(outcomes) do
    Enum.reduce(
      outcomes,
      %{accepted: 0, duplicates: 0, rejected: 0, outcomes: outcomes},
      fn outcome, acc ->
        Map.update!(acc, status_bucket(outcome.status), &(&1 + 1))
      end
    )
  end

  defp status_bucket(:accepted), do: :accepted
  defp status_bucket(:duplicate), do: :duplicates
  defp status_bucket(:rejected), do: :rejected

  @doc "Total received events across all workspaces (cheap; indexed count)."
  @spec count() :: non_neg_integer()
  def count do
    Repo.aggregate(ReceivedTelemetryEvent, :count, :id)
  end

  # --- Workspace-scoped variants (tenant-facing) ---

  @doc "Recent received events for a workspace, newest first."
  @spec recent(String.t(), keyword()) :: [ReceivedTelemetryEvent.t()]
  def recent(workspace_id, opts \\ []) when is_binary(workspace_id) do
    limit = Keyword.get(opts, :limit, 50)

    ReceivedTelemetryEvent
    |> where([e], e.workspace_id == ^workspace_id)
    |> order_by([e], desc: e.received_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  # --- Global admin variants (operator dashboard only) ---

  @doc """
  Recent received events across ALL workspaces, newest first.

  **Admin only.** Use `recent(workspace_id, opts)` for tenant-facing surfaces.
  """
  @spec global_recent(keyword()) :: [ReceivedTelemetryEvent.t()]
  def global_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    ReceivedTelemetryEvent
    |> order_by([e], desc: e.received_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Recent received events scoped to a single enrolled workspace_id."
  @spec recent_for_workspace(String.t(), keyword()) :: [ReceivedTelemetryEvent.t()]
  def recent_for_workspace(workspace_id, opts \\ []) when is_binary(workspace_id) do
    recent(workspace_id, opts)
  end

  @doc "Per-kind event counts for a single workspace_id."
  @spec counts_for_workspace(String.t()) :: %{String.t() => non_neg_integer()}
  def counts_for_workspace(workspace_id) when is_binary(workspace_id) do
    ReceivedTelemetryEvent
    |> where([e], e.workspace_id == ^workspace_id)
    |> group_by([e], e.kind)
    |> select([e], {e.kind, count(e.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Funnel metrics for a single workspace.

  Returns counts by event kind plus high-level funnel stages
  (install → attach → first finding).
  """
  @spec funnel_metrics(String.t()) :: %{
          total: non_neg_integer(),
          by_kind: [{String.t(), non_neg_integer()}],
          workspaces: non_neg_integer(),
          install_success: non_neg_integer(),
          attach_success: non_neg_integer(),
          first_findings: non_neg_integer(),
          last_received_at: DateTime.t() | nil
        }
  def funnel_metrics(workspace_id) when is_binary(workspace_id) do
    build_funnel_metrics(where(ReceivedTelemetryEvent, [e], e.workspace_id == ^workspace_id))
  end

  @doc """
  Funnel metrics across ALL workspaces.

  **Admin only.** Use `funnel_metrics(workspace_id)` for tenant-facing surfaces.
  """
  @spec global_funnel_metrics() :: %{
          total: non_neg_integer(),
          by_kind: [{String.t(), non_neg_integer()}],
          workspaces: non_neg_integer(),
          install_success: non_neg_integer(),
          attach_success: non_neg_integer(),
          first_findings: non_neg_integer(),
          last_received_at: DateTime.t() | nil
        }
  def global_funnel_metrics do
    build_funnel_metrics(ReceivedTelemetryEvent)
  end

  defp build_funnel_metrics(base_query) do
    by_kind =
      base_query
      |> group_by([e], e.kind)
      |> select([e], {e.kind, count(e.id)})
      |> Repo.all()
      |> Enum.sort_by(&elem(&1, 1), :desc)

    by_kind_map = Map.new(by_kind)
    total = by_kind_map |> Map.values() |> Enum.sum()

    workspaces =
      base_query
      |> select([e], count(e.workspace_id, :distinct))
      |> Repo.one() || 0

    last_received_at =
      base_query
      |> select([e], max(e.received_at))
      |> Repo.one()

    %{
      total: total,
      by_kind: by_kind,
      workspaces: workspaces,
      install_success: Map.get(by_kind_map, "install.success", 0),
      attach_success: Map.get(by_kind_map, "attach.success", 0),
      first_findings: Map.get(by_kind_map, "finding.created", 0),
      last_received_at: last_received_at
    }
  end
end
