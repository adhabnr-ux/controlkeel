defmodule ControlKeel.Cloud.TelemetryQueue do
  @moduledoc """
  Durable local queue for cloud telemetry events awaiting upstream sync.

  Events enter the queue via `enqueue/1` with a fully-built D3 envelope (see
  `ControlKeel.Cloud.TelemetryEnvelope`). The sender (a later slice) drains the
  queue by reading `pending/1`, posting upstream, then calling `mark_sent/1` or
  `mark_failed/2`.

  Idempotency is enforced at two layers:

    1. Unique index on `event_id` and `idempotency_key` — a duplicate insert is
       a no-op (returns the existing row).
    2. `mark_sent/1` is conditional on the row still being pending so concurrent
       senders cannot double-acknowledge.

  Retention: `prune/1` removes events whose `sent_at` is older than the retention
  window (default 7 days, matching the D3 dedupe window). Unsent events are
  never pruned — operators must explicitly `discard/1` them.

  All operations are local SQLite; no network calls.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Cloud.TelemetryEvent
  alias ControlKeel.Repo

  @default_retention_days 7

  @doc """
  Enqueue a telemetry envelope.

  Returns `{:ok, :enqueued, event}` on first insert,
  `{:ok, :duplicate, existing}` when an event with the same `event_id` already
  exists (idempotent — caller can ignore safely).
  """
  @spec enqueue(map()) ::
          {:ok, :enqueued | :duplicate, TelemetryEvent.t()}
          | {:error, Ecto.Changeset.t()}
  def enqueue(envelope) when is_map(envelope) do
    attrs = envelope_to_attrs(envelope)

    case Repo.get_by(TelemetryEvent, event_id: attrs.event_id) do
      nil ->
        case %TelemetryEvent{}
             |> TelemetryEvent.changeset(attrs)
             |> Repo.insert() do
          {:ok, event} ->
            {:ok, :enqueued, event}

          {:error, %Ecto.Changeset{errors: errors}} = err ->
            if Keyword.has_key?(errors, :event_id) or
                 Keyword.has_key?(errors, :idempotency_key) do
              # Lost a race; treat as duplicate.
              existing = Repo.get_by!(TelemetryEvent, event_id: attrs.event_id)
              {:ok, :duplicate, existing}
            else
              err
            end
        end

      existing ->
        {:ok, :duplicate, existing}
    end
  end

  @doc """
  List pending (unsent) events ordered by oldest first.

  Pass `limit:` to cap the batch size for senders.
  """
  @spec pending(keyword()) :: [TelemetryEvent.t()]
  def pending(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    TelemetryEvent
    |> where([e], is_nil(e.sent_at))
    |> order_by([e], asc: e.queued_at, asc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Number of pending events. Cheap; uses an indexed count."
  @spec pending_count() :: non_neg_integer()
  def pending_count do
    TelemetryEvent
    |> where([e], is_nil(e.sent_at))
    |> select([e], count(e.id))
    |> Repo.one()
  end

  @doc """
  Mark an event as successfully sent.

  Returns `{:ok, event}` when the row was pending, `{:error, :already_sent}`
  when it was already acknowledged (defends against double-ack from concurrent
  senders).
  """
  @spec mark_sent(TelemetryEvent.t() | integer()) ::
          {:ok, TelemetryEvent.t()} | {:error, :already_sent | :not_found}
  def mark_sent(%TelemetryEvent{id: id}), do: mark_sent(id)

  def mark_sent(id) when is_integer(id) do
    case Repo.get(TelemetryEvent, id) do
      nil ->
        {:error, :not_found}

      %TelemetryEvent{sent_at: %DateTime{}} ->
        {:error, :already_sent}

      event ->
        event
        |> TelemetryEvent.changeset(%{
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
          send_attempts: event.send_attempts + 1,
          last_error: nil
        })
        |> Repo.update()
    end
  end

  @doc "Record a failed send attempt without marking the event as sent."
  @spec mark_failed(TelemetryEvent.t() | integer(), String.t()) ::
          {:ok, TelemetryEvent.t()} | {:error, term()}
  def mark_failed(%TelemetryEvent{id: id}, reason), do: mark_failed(id, reason)

  def mark_failed(id, reason) when is_integer(id) and is_binary(reason) do
    case Repo.get(TelemetryEvent, id) do
      nil ->
        {:error, :not_found}

      event ->
        event
        |> TelemetryEvent.changeset(%{
          send_attempts: event.send_attempts + 1,
          last_error: reason
        })
        |> Repo.update()
    end
  end

  @doc """
  Delete sent events older than the retention window.

  Returns `{deleted_count, nil}`. Unsent events are never deleted by prune.
  """
  @spec prune(keyword()) :: {non_neg_integer(), nil}
  def prune(opts \\ []) do
    days = Keyword.get(opts, :retention_days, @default_retention_days)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86_400, :second)

    TelemetryEvent
    |> where([e], not is_nil(e.sent_at) and e.sent_at < ^cutoff)
    |> Repo.delete_all()
  end

  @doc """
  Discard an unsent event without sending it. Use for operator overrides.
  """
  @spec discard(TelemetryEvent.t() | integer()) :: {non_neg_integer(), nil}
  def discard(%TelemetryEvent{id: id}), do: discard(id)
  def discard(id) when is_integer(id), do: Repo.delete_all(from e in TelemetryEvent, where: e.id == ^id)

  defp envelope_to_attrs(envelope) do
    %{
      event_id: fetch!(envelope, "event_id"),
      workspace_id: fetch!(envelope, "workspace_id"),
      kind: fetch!(envelope, "kind"),
      emitted_at: parse_emitted_at(fetch!(envelope, "emitted_at")),
      idempotency_key: fetch!(envelope, "idempotency_key"),
      redaction_policy_version: fetch!(envelope, "redaction_policy_version"),
      schema_version: fetch!(envelope, "schema_version"),
      body: Jason.encode!(envelope),
      queued_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }
  end

  defp fetch!(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} when not is_nil(value) -> value
      _ -> raise ArgumentError, "envelope missing required key #{inspect(key)}"
    end
  end

  defp parse_emitted_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> raise ArgumentError, "invalid emitted_at: #{inspect(value)}"
    end
  end

  defp parse_emitted_at(%DateTime{} = dt), do: DateTime.truncate(dt, :second)
  defp parse_emitted_at(other), do: raise(ArgumentError, "invalid emitted_at: #{inspect(other)}")
end
