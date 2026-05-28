defmodule ControlKeel.Cloud.SyncEngine do
  @moduledoc """
  GenServer that orchestrates periodic bidirectional cloud sync.

  On a configurable interval (default 30s), it:
    1. Collects unsynced local records via Cloud.Sync
    2. Pushes them to the configured cloud sync endpoint
    3. Pulls any new records from cloud since last sync
    4. Upserts pulled records locally

  Can also be triggered manually via :sync message or from CLI.
  """

  use GenServer

  require Logger

  alias ControlKeel.Cloud.{AuthToken, Sync, WorkspaceIdentity}

  @default_interval_ms 30_000

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
      Logger.info("[SyncEngine] No cloud sync endpoint configured — staying dormant")
      {:ok, state}
    end
  end

  @impl true
  def handle_call(:sync, _from, %{syncing: true} = state) do
    {:reply, {:error, :already_syncing}, state}
  end

  def handle_call(:sync, _from, state) do
    result = do_sync(state)
    {:reply, result, %{state | last_synced_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.endpoint do
      _ = do_sync(state)
      Process.send_after(self(), :tick, state.interval_ms)
    end

    {:noreply, %{state | last_synced_at: DateTime.utc_now()}}
  end

  # ── Sync logic ─────────────────────────────────────────────────────

  defp do_sync(state) do
    case WorkspaceIdentity.load() do
      {:ok, identity} ->
        push_result = push_unsynced(identity)

        pull_result =
          case state.last_synced_at do
            nil -> %{total: 0}
            since -> pull_from_cloud(identity, since)
          end

        {:ok, %{push: push_result, pull: pull_result}}

      {:error, :not_connected} ->
        {:error, :not_enrolled}
    end
  end

  defp push_unsynced(identity) do
    case Sync.collect_unsynced(identity.workspace_id) do
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
        Sync.upsert_batch(records)

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

  defp sync_endpoint do
    base = Application.get_env(:controlkeel, :cloud_sync_endpoint)

    if base && base != "" do
      String.trim_trailing(base, "/") <> "/cloud/v1/sync"
    else
      nil
    end
  end
end
