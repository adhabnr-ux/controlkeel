defmodule ControlKeel.Cloud.SyncEngine do
  @moduledoc """
  GenServer orchestrating periodic bidirectional cloud sync.

  On a configurable interval (default 30s) it:

    1. Resolves the local Mission.Workspace id from the enrolled identity via
       `KeyRegistry.fetch/1`. If no mapping exists, the engine logs
       and skips the tick.
    2. Collects unsynced local records via `Cloud.Sync.collect_unsynced/2`.
    3. Pushes them to the configured cloud sync endpoint.
    4. Pulls records updated since the last *successful* sync from cloud.
    5. Upserts pulled records locally inside `Cloud.Sync.upsert_batch/2`.

  Invariants:

    * `state.syncing` is `true` for the duration of a sync; concurrent
      `force_sync/0` calls return `{:error, :already_syncing}`.
    * `state.last_synced_at` advances **only** on `{:ok, _}` from `do_sync/1`.
      A failed sync does not move the cursor; the next attempt will refetch
      everything it missed.
    * The first ever sync uses `~U[1970-01-01 00:00:00Z]` as the pull cursor,
      so initial pulls actually fetch records.
    * Without `:cloud_sync_endpoint` configured the engine starts dormant and
      logs that fact at info level. Manual `force_sync/0` calls return
      `{:error, :not_configured}`.
  """

  use GenServer

  require Logger

  alias ControlKeel.Cloud.{AuthToken, Sync, Workspace.Identity, Workspace.KeyRegistry}
  alias ControlKeel.Runtime.Mode

  @default_interval_ms 30_000
  @epoch ~U[1970-01-01 00:00:00Z]

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def force_sync(server \\ __MODULE__) do
    GenServer.call(server, :sync, 60_000)
  end

  # ── GenServer callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, @default_interval_ms)
    endpoint = sync_endpoint()

    state = %{
      interval_ms: interval,
      endpoint: endpoint,
      last_synced_at: nil,
      syncing: false
    }

    if endpoint do
      Process.send_after(self(), :tick, interval)
      {:ok, state}
    else
      Logger.info("[SyncEngine] no cloud sync endpoint configured — staying dormant")
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:sync, _from, %{syncing: true} = state) do
    {:reply, {:error, :already_syncing}, state}
  end

  def handle_call(:sync, _from, %{endpoint: nil} = state) do
    {:reply, {:error, :not_configured}, state}
  end

  def handle_call(:sync, _from, state) do
    {result, new_state} = run_sync(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state =
      cond do
        state.syncing ->
          state

        is_nil(state.endpoint) ->
          state

        true ->
          {_result, s} = run_sync(state)
          s
      end

    if new_state.endpoint do
      Process.send_after(self(), :tick, new_state.interval_ms)
    end

    {:noreply, new_state}
  end

  # ── Sync logic ─────────────────────────────────────────────────────

  # Wraps do_sync with the `syncing` flag and the success-gated cursor advance.
  defp run_sync(state) do
    started_at = DateTime.utc_now()
    busy_state = %{state | syncing: true}
    result = do_sync(busy_state)

    finished_state = %{
      busy_state
      | syncing: false,
        last_synced_at: maybe_advance_cursor(state.last_synced_at, result, started_at)
    }

    {result, finished_state}
  end

  defp maybe_advance_cursor(_prior, {:ok, _}, started_at), do: started_at
  defp maybe_advance_cursor(prior, _err, _started_at), do: prior

  defp do_sync(%{endpoint: nil}), do: {:error, :not_configured}

  defp do_sync(state) do
    case Identity.load() do
      {:ok, identity} ->
        case resolve_db_workspace_id(identity) do
          nil ->
            {:error, :workspace_not_enrolled}

          db_workspace_id ->
            push_result = push_unsynced(identity, db_workspace_id)
            pull_result = pull_from_cloud(identity, state.last_synced_at || @epoch)
            {:ok, %{push: push_result, pull: pull_result}}
        end

      {:error, :not_connected} ->
        {:error, :not_enrolled}

      {:error, other} ->
        {:error, other}
    end
  end

  defp push_unsynced(identity, db_workspace_id) do
    case Sync.collect_unsynced(db_workspace_id) do
      %{total: 0} ->
        %{pushed: 0}

      %{total: count, records: records} ->
        envelopes = Enum.map(records, &Sync.serialize_record/1)

        case send_to_cloud(identity, envelopes) do
          :ok ->
            Sync.mark_synced(records)
            %{pushed: count}

          {:error, reason} ->
            %{pushed: 0, error: reason}
        end
    end
  end

  defp pull_from_cloud(identity, since) do
    endpoint = sync_endpoint()
    since_iso = DateTime.to_iso8601(since)

    body = %{
      workspace_id: identity.workspace_id,
      since: since_iso,
      action: "pull"
    }

    http_module = Application.get_env(:controlkeel, :cloud_sync_http_module, Req)

    case http_module.post("#{endpoint}/pull",
           json: body,
           headers: auth_headers(identity),
           receive_timeout: 15_000
         ) do
      {:ok, %{status: status, body: resp}} when status in 200..299 ->
        records = Map.get(resp, "records", [])

        case Sync.upsert_batch(records) do
          {:ok, summary} -> summary
          {:error, reason} -> %{total: 0, error: inspect(reason)}
        end

      {:ok, %{status: status}} ->
        %{total: 0, error: "cloud returned #{status}"}

      {:error, reason} ->
        %{total: 0, error: inspect(reason)}
    end
  end

  defp send_to_cloud(identity, envelopes) do
    endpoint = sync_endpoint()

    body = %{
      workspace_id: identity.workspace_id,
      records: envelopes
    }

    http_module = Application.get_env(:controlkeel, :cloud_sync_http_module, Req)

    case http_module.post("#{endpoint}/push",
           json: body,
           headers: auth_headers(identity),
           receive_timeout: 30_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, "cloud returned #{status}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp auth_headers(identity) do
    {:ok, token} = AuthToken.sign(identity)

    [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]
  end

  # Cloud identity holds the cloud-side workspace id (string UUID). The local
  # DB uses Mission.Workspace.id (integer). The bridge is the
  # KeyRegistry record's mission_workspace_id, written at enrollment.
  defp resolve_db_workspace_id(%{workspace_id: ws_id}) when is_binary(ws_id) do
    case KeyRegistry.fetch(ws_id) do
      {:ok, %{mission_workspace_id: id}} when is_integer(id) -> id
      _ -> nil
    end
  end

  defp resolve_db_workspace_id(_), do: nil

  defp sync_endpoint do
    base =
      Application.get_env(:controlkeel, :cloud_sync_endpoint) ||
        System.get_env("CONTROLKEEL_CLOUD_SYNC_ENDPOINT")

    case Mode.normalize_sync_endpoint(base, Mode.current()) do
      {:ok, endpoint} -> endpoint <> "/cloud/v1/sync"
      {:error, _reason} -> nil
    end
  end
end
