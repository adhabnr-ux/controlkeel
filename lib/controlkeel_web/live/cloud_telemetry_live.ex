defmodule ControlKeelWeb.CloudTelemetryLive do
  @moduledoc """
  Mission Control LiveView for cloud telemetry ingestion health.

  Shows install-to-first-finding funnel, queue depth (outbound), received
  events (inbound), and recent activity. Read-only — no actions on this view.

  Phase 2 acceptance gate: "Dashboard renders install-to-first-finding funnel
  for a seeded workspace."
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Cloud.Ingestion
  alias ControlKeel.Cloud.Sender
  alias ControlKeel.Cloud.TelemetryConfig
  alias ControlKeel.Cloud.TelemetryQueue
  alias ControlKeel.Cloud.WorkspaceIdentity

  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)

    {:ok,
     socket
     |> assign(:page_title, "Cloud telemetry")
     |> assign_view_state()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, assign_view_state(socket)}
  end

  defp assign_view_state(socket) do
    metrics = Ingestion.funnel_metrics()
    queue_depth = TelemetryQueue.pending_count()
    telemetry_state = TelemetryConfig.load()
    endpoint = Sender.endpoint()
    identity_summary = identity_summary()

    socket
    |> assign(:metrics, metrics)
    |> assign(:queue_depth, queue_depth)
    |> assign(:telemetry_state, telemetry_state)
    |> assign(:endpoint, endpoint)
    |> assign(:identity_summary, identity_summary)
    |> assign(:recent_events, Ingestion.recent(limit: 25))
  end

  defp identity_summary do
    case WorkspaceIdentity.load() do
      {:ok, identity} ->
        %{
          status: :connected,
          workspace_id: identity.workspace_id,
          fingerprint: WorkspaceIdentity.short_fingerprint(identity)
        }

      {:error, :not_connected} ->
        %{status: :not_connected}

      {:error, _} ->
        %{status: :malformed}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="cloud-telemetry-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Cloud</p>
            <h1 class="ck-section-title">Cloud telemetry</h1>
            <p class="ck-lead ck-lead-tight">
              Local-first by design. Cloud sync is opt-in per workspace.
            </p>
          </div>
          <div class="ck-badge-stack">
            <span class={telemetry_pill_class(@telemetry_state.level)}>
              {@telemetry_state.level}
            </span>
            <span class="ck-pill ck-pill-neutral">{@metrics.total} received</span>
            <span class="ck-pill ck-pill-neutral">{@queue_depth} pending</span>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div id="cloud-telemetry-identity" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Workspace identity</p>
            {render_identity(assigns)}
          </div>

          <div id="cloud-telemetry-endpoint" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Endpoint</p>
            <strong>{@endpoint || "unconfigured"}</strong>
            <p class="ck-note">
              {if @endpoint, do: "drainer will POST batches here", else: "set :cloud_telemetry_endpoint to enable sync"}
            </p>
          </div>

          <div id="cloud-telemetry-queue" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Outbound queue</p>
            <strong>{@queue_depth} pending</strong>
            <p class="ck-note">Persistent, idempotent, retried on backoff</p>
          </div>

          <div id="cloud-telemetry-received" class="ck-card ck-stat-card">
            <p class="ck-mini-label">Received total</p>
            <strong>{@metrics.total}</strong>
            <p class="ck-note">
              across {@metrics.workspaces} workspace(s){last_seen_note(@metrics.last_received_at)}
            </p>
          </div>
        </div>

        <div id="cloud-telemetry-funnel" class="ck-card">
          <h2 class="ck-card-title">Install → attach → first finding funnel</h2>
          <table class="ck-table">
            <thead>
              <tr>
                <th>Stage</th>
                <th>Event kind</th>
                <th class="ck-table-right">Count</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td>1. Install</td>
                <td><code>install.success</code></td>
                <td class="ck-table-right">{@metrics.install_success}</td>
              </tr>
              <tr>
                <td>2. Attach</td>
                <td><code>attach.success</code></td>
                <td class="ck-table-right">{@metrics.attach_success}</td>
              </tr>
              <tr>
                <td>3. First finding</td>
                <td><code>finding.created</code></td>
                <td class="ck-table-right">{@metrics.first_findings}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div id="cloud-telemetry-by-kind" class="ck-card">
          <h2 class="ck-card-title">All event kinds</h2>
          <%= if @metrics.by_kind == [] do %>
            <p class="ck-note">No events received yet.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Kind</th>
                  <th class="ck-table-right">Count</th>
                </tr>
              </thead>
              <tbody>
                <%= for {kind, count} <- @metrics.by_kind do %>
                  <tr>
                    <td><code>{kind}</code></td>
                    <td class="ck-table-right">{count}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <div id="cloud-telemetry-recent" class="ck-card">
          <h2 class="ck-card-title">Recent received events</h2>
          <%= if @recent_events == [] do %>
            <p class="ck-note">No events received yet.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Received at</th>
                  <th>Kind</th>
                  <th>Workspace</th>
                  <th>Event ID</th>
                </tr>
              </thead>
              <tbody>
                <%= for event <- @recent_events do %>
                  <tr>
                    <td>{DateTime.to_iso8601(event.received_at)}</td>
                    <td><code>{event.kind}</code></td>
                    <td><code>{event.workspace_id}</code></td>
                    <td><code>{String.slice(event.event_id, 0, 16)}...</code></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp render_identity(%{identity_summary: %{status: :connected, workspace_id: ws, fingerprint: fp}} = assigns) do
    assigns = assign(assigns, ws: ws, fp: fp)

    ~H"""
    <strong>{@ws}</strong>
    <p class="ck-note">fingerprint {@fp}…</p>
    """
  end

  defp render_identity(%{identity_summary: %{status: :not_connected}} = assigns) do
    ~H"""
    <strong>not connected</strong>
    <p class="ck-note">run <code>controlkeel cloud connect</code></p>
    """
  end

  defp render_identity(assigns) do
    ~H"""
    <strong>error</strong>
    <p class="ck-note">identity file malformed</p>
    """
  end

  defp telemetry_pill_class(:disabled), do: "ck-pill ck-pill-neutral"
  defp telemetry_pill_class(_other), do: "ck-pill ck-pill-success"

  defp last_seen_note(nil), do: ""
  defp last_seen_note(%DateTime{} = ts), do: ", last #{DateTime.to_iso8601(ts)}"
end
