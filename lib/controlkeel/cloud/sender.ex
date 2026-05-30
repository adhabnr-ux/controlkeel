defmodule ControlKeel.Cloud.Sender do
  @moduledoc """
  HTTP sender for the cloud telemetry queue.

  Drains `ControlKeel.Cloud.TelemetryQueue` by posting batches to a configured
  upstream endpoint. The endpoint defaults to `nil`, in which case the sender
  is a no-op so this module can ship before any cloud control plane exists.

  ## Configuration

      config :controlkeel,
        cloud_telemetry_endpoint: "https://cloud.example.com/v1/telemetry",
        cloud_telemetry_timeout_ms: 5_000

  When `cloud_telemetry_endpoint` is `nil`, `flush/0` returns
  `{:ok, :no_endpoint, 0}` without reading the queue.

  ## Wire protocol

  POST `<endpoint>` with JSON body:

      {
        "schema_version": "1",
        "workspace_id": "ws_...",
        "events": [<envelope>, <envelope>, ...]
      }

  Headers:

    - `Authorization: Bearer <workspace_id>` (placeholder; will be replaced by
      a workspace-keypair-signed token in a follow-up slice once the server
      side supports it)
    - `Content-Type: application/json`
    - `Idempotency-Key: <batch-ULID>` (so the server can dedupe whole batches
      under retry; individual events also carry their own idempotency_key)

  Server is expected to return:

    - `2xx` → all events in the batch are marked sent
    - `4xx` → all events are marked failed (will not retry until operator
      resolves the underlying issue)
    - `5xx`, network error, timeout → all events are marked failed (eligible
      for retry on the next flush)

  Idempotency at the server side is the responsibility of the receiver — we
  guarantee that retries carry the same `event_id` and `idempotency_key`.
  """

  require Logger

  alias ControlKeel.Cloud.AuthToken
  alias ControlKeel.Cloud.TelemetryEnvelope
  alias ControlKeel.Cloud.TelemetryEvent
  alias ControlKeel.Cloud.TelemetryQueue
  alias ControlKeel.Cloud.WorkspaceIdentity

  @default_batch_size 100
  @default_timeout_ms 5_000
  @schema_version "1"

  @typedoc "Flush outcome."
  @type flush_result ::
          {:ok, :no_endpoint, 0}
          | {:ok, :no_pending, 0}
          | {:ok, :sent, non_neg_integer()}
          | {:error, :not_connected | :network | {:server, integer()}, non_neg_integer()}

  @doc "Endpoint URL from runtime config, or `nil` when unconfigured."
  @spec endpoint() :: String.t() | nil
  def endpoint do
    case Application.get_env(:controlkeel, :cloud_telemetry_endpoint) do
      nil -> nil
      "" -> nil
      url when is_binary(url) -> url
    end
  end

  @doc """
  Drain up to `:limit` pending events and post them to the configured endpoint.

  Returns:

    - `{:ok, :no_endpoint, 0}` — no endpoint configured (no-op)
    - `{:ok, :no_pending, 0}` — queue empty
    - `{:ok, :sent, n}` — `n` events successfully marked sent
    - `{:error, reason, n}` — `n` events marked failed with the given reason

  This is intentionally synchronous so callers (CLI flush, scheduled drain
  loops) can observe the outcome and surface it. A background drainer can wrap
  this in its own process.
  """
  @spec flush(keyword()) :: flush_result()
  def flush(opts \\ []) do
    case endpoint() do
      nil ->
        {:ok, :no_endpoint, 0}

      url ->
        case WorkspaceIdentity.load() do
          {:error, :not_connected} ->
            {:error, :not_connected, 0}

          {:error, _} ->
            {:error, :not_connected, 0}

          {:ok, identity} ->
            do_flush(url, identity, opts)
        end
    end
  end

  defp do_flush(url, identity, opts) do
    limit = Keyword.get(opts, :limit, @default_batch_size)
    timeout = Keyword.get(opts, :timeout_ms, configured_timeout())
    pending = TelemetryQueue.pending(limit: limit)

    case pending do
      [] ->
        {:ok, :no_pending, 0}

      events ->
        send_batch(url, identity, events, timeout)
    end
  end

  defp send_batch(url, identity, events, timeout) do
    batch_id = TelemetryEnvelope.ulid()
    body = build_batch_body(identity, events)

    case AuthToken.sign(identity) do
      {:ok, token} ->
        headers = [
          {"authorization", "Bearer #{token}"},
          {"content-type", "application/json"},
          {"idempotency-key", batch_id}
        ]

        do_post_batch(url, body, headers, events, timeout)

      {:error, reason} ->
        Logger.warning("Cloud.Sender: failed to sign auth token: #{inspect(reason)}")
        record_failures(events, "failed to sign auth token: #{inspect(reason)}")
        {:error, :network, length(events)}
    end
  end

  defp do_post_batch(url, body, headers, events, timeout) do
    case post(url, body, headers, timeout) do
      {:ok, status} when status in 200..299 ->
        ack_sent(events)
        {:ok, :sent, length(events)}

      {:ok, status} when status in 400..499 ->
        record_failures(events, "server rejected batch with status #{status}")
        {:error, {:server, status}, length(events)}

      {:ok, status} ->
        record_failures(events, "server transient error status #{status}")
        {:error, {:server, status}, length(events)}

      {:error, reason} ->
        record_failures(events, "network error: #{inspect(reason)}")
        {:error, :network, length(events)}
    end
  end

  defp build_batch_body(identity, events) do
    %{
      "schema_version" => @schema_version,
      "workspace_id" => identity.workspace_id,
      "events" => Enum.map(events, &decode_envelope/1)
    }
  end

  defp decode_envelope(%TelemetryEvent{body: body}), do: Jason.decode!(body)

  defp post(url, json_body, headers, timeout) do
    req_module = Application.get_env(:controlkeel, :cloud_sender_http_module, Req)

    case req_module.post(url, json: json_body, headers: headers, receive_timeout: timeout) do
      {:ok, %{status: status}} -> {:ok, status}
      {:error, %{__exception__: true} = error} -> {:error, Exception.message(error)}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp ack_sent(events) do
    Enum.each(events, fn event ->
      case TelemetryQueue.mark_sent(event) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Cloud.Sender: failed to mark event #{event.event_id} sent: #{inspect(reason)}"
          )
      end
    end)
  end

  defp record_failures(events, reason) do
    Enum.each(events, fn event ->
      _ = TelemetryQueue.mark_failed(event, reason)
    end)
  end

  defp configured_timeout do
    Application.get_env(:controlkeel, :cloud_telemetry_timeout_ms, @default_timeout_ms)
  end
end
