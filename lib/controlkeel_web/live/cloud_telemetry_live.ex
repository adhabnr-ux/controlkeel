defmodule ControlKeelWeb.CloudTelemetryLive do
  @moduledoc """
  Mission Control LiveView for cloud telemetry ingestion health.

  Shows install-to-first-finding funnel, queue depth (outbound), received
  events (inbound), and recent activity. Read-only — no actions on this view.

  Phase 2 acceptance gate: "Dashboard renders install-to-first-finding funnel
  for a seeded workspace."
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Budget
  alias ControlKeel.Platform
  alias ControlKeel.ProviderConfig
  alias ControlKeel.Cloud.BaselineAnalyzer
  alias ControlKeel.Cloud.Guardrails
  alias ControlKeel.Cloud.WorkspaceBaseline
  alias ControlKeel.Cloud.Ingestion
  alias ControlKeel.Cloud.McpAuditLog
  alias ControlKeel.Cloud.McpRegistry
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Cloud.Sender
  alias ControlKeel.Cloud.TelemetryConfig
  alias ControlKeel.Cloud.TelemetryQueue
  alias ControlKeel.Cloud.WorkspaceIdentity

  @refresh_ms 5_000

  @impl true
  def mount(_params, session, socket) do
    # Admin-only: operator dashboard shows cross-tenant data.
    # Require an active org membership with admin role.
    membership = resolve_membership(socket, session)

    if admin?(membership) do
      if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)

      {:ok,
       socket
       |> assign(:page_title, "Cloud telemetry")
       |> assign_view_state()}
    else
      {:ok,
       socket
       |> assign(:page_title, "Cloud telemetry")
       |> put_flash(:error, "Admin access required.")
       |> redirect(to: "/")}
    end
  end

  defp admin?(%ControlKeel.Accounts.Membership{status: "active", role: role}),
    do: ControlKeel.Accounts.role_at_least?(role, "admin")

  defp admin?(_), do: false

  defp resolve_membership(socket, session) do
    # Prefer pre-loaded assign from LoadCurrentUser plug (production),
    # fall back to session-based resolution (test / edge cases).
    case socket.assigns[:current_membership] do
      %ControlKeel.Accounts.Membership{} = m ->
        m

      nil ->
        user_id = Map.get(session, "current_user_id") || Map.get(session, :current_user_id)
        org_id = Map.get(session, "current_org_id") || Map.get(session, :current_org_id)

        if is_integer(user_id) and is_integer(org_id) do
          Accounts.get_active_membership(user_id, org_id)
        end
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, assign_view_state(socket)}
  end

  defp assign_view_state(socket) do
    metrics = Ingestion.global_funnel_metrics()
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
    |> assign(:recent_events, Ingestion.global_recent(limit: 25))
    |> assign(:mcp_audit_summary, McpAuditLog.global_summary())
    |> assign(:mcp_audit_by_tool, McpAuditLog.global_counts_by_tool())
    |> assign(:mcp_audit_recent, McpAuditLog.global_recent(limit: 25))
    |> assign(:mcp_registry_summary, McpRegistry.summary())
    |> assign(:mcp_registry_entries, McpRegistry.entries())
    |> assign(:mcp_registry_denylist, McpRegistry.denylist())
    |> assign(:guardrails_summary, Guardrails.summary())
    |> assign(:org_budgets, org_budget_overviews())
    |> assign(:cloud_runs_summary, RuntimeContext.global_status_counts())
    |> assign(:cloud_runs_recent, RuntimeContext.global_recent(limit: 15))
    |> assign(:amplification_ratios, Budget.amplification_ratios(limit: 10, since_hours: 24))
    |> assign(:behavioral_baselines, load_behavioral_baselines())
    |> assign(:fallback_chain, load_fallback_chain())
    |> assign(:nhi_summaries, load_nhi_summaries())
  end

  defp org_budget_overviews do
    Accounts.list_orgs(status: "active")
    |> Enum.map(fn org ->
      status = Accounts.org_budget_status(org.id)
      breakdown = Accounts.org_workspace_breakdown(org.id)
      idp = Accounts.get_org_identity_provider(org)

      Map.merge(status, %{
        org_name: org.name,
        org_slug: org.slug,
        workspaces: breakdown,
        idp_type: idp && idp["type"]
      })
    end)
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
              {if @endpoint,
                do: "drainer will POST batches here",
                else: "set :cloud_telemetry_endpoint to enable sync"}
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

        <div id="cloud-agent-runs" class="ck-card">
          <h2 class="ck-card-title">Cloud-agent run packages</h2>
          <p class="ck-note">
            <%= for {status, count} <- Enum.sort(@cloud_runs_summary) do %>
              <strong>{status}</strong>: {count} ·
            <% end %>
            <%= if @cloud_runs_summary == %{} do %>
              No cloud-agent runs yet.
            <% end %>
          </p>

          <%= if @cloud_runs_recent != [] do %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Package</th>
                  <th>Runtime</th>
                  <th>Status</th>
                  <th>Task</th>
                  <th>Workspace</th>
                  <th>Created</th>
                </tr>
              </thead>
              <tbody>
                <%= for pkg <- @cloud_runs_recent do %>
                  <tr>
                    <td><code>#{pkg.id}</code></td>
                    <td><code>{pkg.runtime_target}</code></td>
                    <td>{pkg.status}</td>
                    <td>{pkg.task_id || "—"}</td>
                    <td>{pkg.workspace_id}</td>
                    <td>{DateTime.to_iso8601(pkg.inserted_at)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <div id="cloud-org-budgets" class="ck-card">
          <h2 class="ck-card-title">Org budget rollup</h2>
          <%= if @org_budgets == [] do %>
            <p class="ck-note">No active orgs.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Org</th>
                  <th class="ck-table-right">Workspaces</th>
                  <th class="ck-table-right">Spent (cents)</th>
                  <th class="ck-table-right">Budget (cents)</th>
                  <th class="ck-table-right">Remaining</th>
                  <th>Status</th>
                  <th>SSO</th>
                </tr>
              </thead>
              <tbody>
                <%= for o <- @org_budgets do %>
                  <tr>
                    <td><code>{o.org_slug}</code> — {o.org_name}</td>
                    <td class="ck-table-right">{o.workspace_count}</td>
                    <td class="ck-table-right">{o.spent_cents}</td>
                    <td class="ck-table-right">{format_cap(o.budget_cents)}</td>
                    <td class="ck-table-right">{format_remaining(o.remaining_cents)}</td>
                    <td>{if o.over_cap?, do: "OVER CAP", else: "ok"}</td>
                    <td>{o.idp_type || "—"}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <div id="cloud-amplification-ratio" class="ck-card">
          <h2 class="ck-card-title">Token amplification ratio (last 24 h)</h2>
          <p class="ck-note">
            output_tokens / input_tokens per session — ratios &gt;&gt; 10 may indicate runaway generation.
          </p>
          <%= if @amplification_ratios == [] do %>
            <p class="ck-note">No invocations recorded in the last 24 hours.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Session</th>
                  <th>Workspace</th>
                  <th class="ck-table-right">Input tokens</th>
                  <th class="ck-table-right">Output tokens</th>
                  <th class="ck-table-right">Ratio</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @amplification_ratios do %>
                  <tr>
                    <td><code>{row.session_id}</code></td>
                    <td><code>{row.workspace_id || "—"}</code></td>
                    <td class="ck-table-right">{row.input_tokens}</td>
                    <td class="ck-table-right">{row.output_tokens}</td>
                    <td class={["ck-table-right", amplification_class(row.ratio)]}>{row.ratio}×</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <div id="cloud-behavioral-baselines" class="ck-card">
          <h2 class="ck-card-title">Behavioral baselines</h2>
          <p class="ck-note">
            Per-workspace tool-usage baselines. Run
            <code>controlkeel baseline compute --workspace-id &lt;id&gt;</code>
            to refresh. Deviations ≥ 3× baseline create findings automatically.
          </p>
          <%= if @behavioral_baselines == [] do %>
            <p class="ck-note">No active workspaces.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Workspace</th>
                  <th>Org</th>
                  <th class="ck-table-right">Tools baselined</th>
                  <th class="ck-table-right">Sample sessions</th>
                  <th>Last computed</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @behavioral_baselines do %>
                  <tr>
                    <td>
                      <code>{row.workspace_id}</code>{if row.workspace_name,
                        do: " — #{row.workspace_name}",
                        else: ""}
                    </td>
                    <td>{row.org_name}</td>
                    <td class="ck-table-right">{row.tool_count}</td>
                    <td class="ck-table-right">{row.sample_sessions || "—"}</td>
                    <td>
                      {if row.computed_at, do: DateTime.to_iso8601(row.computed_at), else: "never"}
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <div id="cloud-mcp-guardrails" class="ck-card">
          <h2 class="ck-card-title">Content guardrails</h2>
          <p class="ck-note">
            enabled: <strong>{@guardrails_summary.enabled}</strong>
            ·
            patterns: {@guardrails_summary.pattern_count}
            {if @guardrails_summary.allow_for_tools == [],
              do: "",
              else: " · allow-for: " <> Enum.join(@guardrails_summary.allow_for_tools, ", ")}
          </p>
          <%= if @guardrails_summary.enabled do %>
            <p class="ck-note">
              Active:
              <%= for name <- @guardrails_summary.patterns do %>
                <code>{name}</code>
              <% end %>
            </p>
          <% else %>
            <p class="ck-note">
              Disabled — set <code>:cloud_mcp_guardrails</code>
              with <code>enabled: true</code>
              to scan tool arguments for secrets.
            </p>
          <% end %>
        </div>

        <div id="cloud-mcp-registry" class="ck-card">
          <h2 class="ck-card-title">Downstream MCP server registry</h2>
          <p class="ck-note">
            default policy: <strong>{@mcp_registry_summary.default_policy}</strong>
            · {@mcp_registry_summary.allowlist_count} allowlisted · {@mcp_registry_summary.requires_attestation} require attestation · {@mcp_registry_summary.denylist_count} denylisted
          </p>
          <%= if @mcp_registry_entries == [] and @mcp_registry_denylist == [] do %>
            <p class="ck-note">No downstream MCP servers configured.</p>
          <% else %>
            <%= if @mcp_registry_entries != [] do %>
              <table class="ck-table">
                <thead>
                  <tr>
                    <th>Allowlisted</th>
                    <th>Attestation</th>
                    <th>URL</th>
                    <th>Note</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for e <- @mcp_registry_entries do %>
                    <tr>
                      <td><code>{e.name}</code></td>
                      <td>{e.attestation}</td>
                      <td><code>{e.url || ""}</code></td>
                      <td>{e.note || ""}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            <% end %>
            <%= if @mcp_registry_denylist != [] do %>
              <p class="ck-note">
                Denylisted:
                <%= for name <- @mcp_registry_denylist do %>
                  <code>{name}</code>
                <% end %>
              </p>
            <% end %>
          <% end %>
        </div>

        <div id="cloud-fallback-chain" class="ck-card">
          <h2 class="ck-card-title">Provider fallback chain</h2>
          <%= if @fallback_chain == [] do %>
            <p class="ck-note">
              No fallback chain configured. Set one with <code>controlkeel provider set-fallback-chain anthropic openai openrouter</code>.
            </p>
          <% else %>
            <ol class="ck-mini-list" style="margin-top: 0.5rem;">
              <%= for {provider, idx} <- Enum.with_index(@fallback_chain, 1) do %>
                <li><strong>#{idx}</strong> <code>{provider}</code></li>
              <% end %>
            </ol>
            <p class="ck-note" style="margin-top: 0.5rem;">
              When a provider's budget is exhausted the next available provider in this chain is selected automatically.
            </p>
          <% end %>
        </div>

        <div id="cloud-nhi-summary" class="ck-card">
          <h2 class="ck-card-title">Non-human identity (NHI) lifecycle</h2>
          <%= if @nhi_summaries == [] do %>
            <p class="ck-note">No service accounts provisioned yet.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Workspace</th>
                  <th>Org</th>
                  <th class="ck-table-right">Total</th>
                  <th class="ck-table-right">Active</th>
                  <th class="ck-table-right">Revoked</th>
                </tr>
              </thead>
              <tbody>
                <%= for summary <- @nhi_summaries do %>
                  <tr>
                    <td>{summary.workspace_name}</td>
                    <td>{summary.org_name}</td>
                    <td class="ck-table-right">{summary.total}</td>
                    <td class="ck-table-right">{summary.active}</td>
                    <td class="ck-table-right">{summary.revoked}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <div id="cloud-mcp-audit-summary" class="ck-card">
          <h2 class="ck-card-title">Hosted MCP / A2A audit</h2>
          <p class="ck-note">
            {@mcp_audit_summary.total} total · {@mcp_audit_summary.allowed} allowed · {@mcp_audit_summary.denied} denied
          </p>
          <%= if @mcp_audit_by_tool == [] do %>
            <p class="ck-note">No hosted MCP / A2A calls recorded yet.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Tool</th>
                  <th class="ck-table-right">Allowed</th>
                  <th class="ck-table-right">Denied</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @mcp_audit_by_tool do %>
                  <tr>
                    <td><code>{row.tool_name}</code></td>
                    <td class="ck-table-right">{row.allowed}</td>
                    <td class="ck-table-right">{row.denied}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>

        <div id="cloud-mcp-audit-recent" class="ck-card">
          <h2 class="ck-card-title">Recent tool dispatches</h2>
          <%= if @mcp_audit_recent == [] do %>
            <p class="ck-note">No calls yet.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Resource</th>
                  <th>Tool</th>
                  <th>Outcome</th>
                  <th>Reason</th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @mcp_audit_recent do %>
                  <tr>
                    <td>{DateTime.to_iso8601(row.requested_at)}</td>
                    <td><code>{row.resource}</code></td>
                    <td><code>{row.tool_name}</code></td>
                    <td>{row.outcome}</td>
                    <td>{row.denial_reason || ""}</td>
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

  defp render_identity(
         %{identity_summary: %{status: :connected, workspace_id: ws, fingerprint: fp}} = assigns
       ) do
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

  defp format_cap(nil), do: "uncapped"
  defp format_cap(n) when is_integer(n), do: Integer.to_string(n)

  defp format_remaining(nil), do: "—"
  defp format_remaining(n) when is_integer(n), do: Integer.to_string(n)

  defp last_seen_note(nil), do: ""
  defp last_seen_note(%DateTime{} = ts), do: ", last #{DateTime.to_iso8601(ts)}"

  defp amplification_class(ratio) when ratio > 20, do: "ck-text-danger"
  defp amplification_class(ratio) when ratio > 5, do: "ck-text-warn"
  defp amplification_class(_ratio), do: ""

  defp load_behavioral_baselines do
    Accounts.list_orgs(status: "active")
    |> Enum.flat_map(fn org ->
      Accounts.org_workspace_breakdown(org.id)
      |> Enum.map(fn ws ->
        baseline = BaselineAnalyzer.get_baseline(ws.workspace_id)

        %{
          workspace_id: ws.workspace_id,
          workspace_name: ws.workspace_name,
          org_name: org.name,
          computed_at: baseline && baseline.computed_at,
          sample_sessions: baseline && baseline.sample_sessions,
          tool_count: baseline_tool_count(baseline)
        }
      end)
    end)
  end

  defp baseline_tool_count(nil), do: 0

  defp baseline_tool_count(baseline) do
    baseline
    |> WorkspaceBaseline.decode()
    |> map_size()
  end

  defp load_fallback_chain do
    case ProviderConfig.read() do
      {:ok, config} -> Map.get(config, "fallback_chain", [])
      _ -> []
    end
  end

  defp load_nhi_summaries do
    Accounts.list_orgs(status: "active")
    |> Enum.flat_map(fn org ->
      Accounts.org_workspace_breakdown(org.id)
      |> Enum.map(fn ws ->
        summary = Platform.nhi_lifecycle_summary(ws.workspace_id)
        Map.merge(summary, %{workspace_name: ws.workspace_name, org_name: org.name})
      end)
    end)
    |> Enum.reject(&(&1.total == 0))
  end
end
