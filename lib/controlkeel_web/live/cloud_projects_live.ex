defmodule ControlKeelWeb.CloudProjectsLive do
  @moduledoc """
  Org-scoped list of enrolled workspaces and per-workspace event detail view.

  Phase 7 (multi-tenant SaaS) acceptance gate: an SSO'd user can land on
  `/cloud/projects`, see the workspaces enrolled under their org, click into
  one, and read the recent telemetry events that workspace has posted.

  Authorization:

    - `:index` requires an active org membership; the org_id pins the list.
    - `:show` resolves the requested workspace_id through
      `WorkspaceKeyRegistry.fetch/1`, then enforces that `key.org_id` matches
      the SSO'd org. Without a session this falls back to the local
      `WorkspaceIdentity` for single-node self-host (the unauthenticated
      page still surfaces the receiver's own workspace).

  This LiveView is intentionally read-only — enrolment happens through the
  CLI (`controlkeel cloud connect --enroll`), not the web UI.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Ingestion
  alias ControlKeel.Cloud.WorkspaceKey
  alias ControlKeel.Cloud.WorkspaceKeyRegistry

  @refresh_ms 5_000

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)

    user_id = Map.get(session, "current_user_id")
    org_id = Map.get(session, "current_org_id")
    user = if is_integer(user_id), do: Accounts.get_user(user_id)

    membership =
      if user && is_integer(org_id), do: Accounts.get_active_membership(user.id, org_id)

    socket =
      socket
      |> assign(:page_title, "Cloud projects")
      |> assign(:current_user, user)
      |> assign(:current_org_id, org_id)
      |> assign(:current_membership, membership)

    case socket.assigns.live_action || :index do
      :show -> mount_show(params, socket)
      _ -> mount_index(socket)
    end
  end

  defp mount_index(socket) do
    keys =
      cond do
        socket.assigns.current_membership ->
          WorkspaceKeyRegistry.list_for_org(socket.assigns.current_org_id)

        true ->
          []
      end

    {:ok,
     socket
     |> assign(:keys, keys)
     |> assign(:state, list_state(socket, keys))}
  end

  defp mount_show(%{"ws_id" => ws_id}, socket) do
    case WorkspaceKeyRegistry.fetch(ws_id) do
      {:ok, key} ->
        cond do
          socket.assigns.current_membership && key.org_id == socket.assigns.current_org_id ->
            {:ok, assign_show_state(socket, key)}

          # Allow operators to inspect unbound (org_id: nil) registrations from
          # the cross-org admin /cloud/telemetry view by following deep links.
          # The Show view doesn't enforce admin role here — it just refuses to
          # render workspaces bound to an org the visitor isn't a member of.
          is_nil(key.org_id) and is_nil(socket.assigns.current_membership) ->
            {:ok, assign_show_state(socket, key)}

          true ->
            {:ok, assign(socket, :state, :forbidden)}
        end

      {:error, :not_found} ->
        {:ok, assign(socket, :state, :not_found)}
    end
  end

  defp assign_show_state(socket, %WorkspaceKey{} = key) do
    events = Ingestion.recent_for_workspace(key.workspace_id, limit: 50)
    counts = Ingestion.counts_for_workspace(key.workspace_id)

    socket
    |> assign(:state, :show)
    |> assign(:key, key)
    |> assign(:events, events)
    |> assign(:counts, counts)
  end

  defp list_state(socket, keys) do
    cond do
      is_nil(socket.assigns.current_user) -> :signed_out
      is_nil(socket.assigns.current_membership) -> :no_membership
      keys == [] -> :empty
      true -> :ready
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    Process.send_after(self(), :refresh, @refresh_ms)

    socket =
      case socket.assigns.live_action || :index do
        :show ->
          case socket.assigns[:key] do
            %WorkspaceKey{} = key -> assign_show_state(socket, key)
            _ -> socket
          end

        _ ->
          keys =
            if socket.assigns.current_membership,
              do: WorkspaceKeyRegistry.list_for_org(socket.assigns.current_org_id),
              else: []

          socket
          |> assign(:keys, keys)
          |> assign(:state, list_state(socket, keys))
      end

    {:noreply, socket}
  end

  @impl true
  def render(%{live_action: :show, state: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="cloud-project-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">
              <.link navigate={~p"/cloud/projects"}>Cloud projects</.link> /
              <code>{@key.workspace_id}</code>
            </p>
            <h1 class="ck-section-title">{@key.name || @key.workspace_id}</h1>
            <p class="ck-lead ck-lead-tight">
              Fingerprint <code>{String.slice(@key.fingerprint, 0, 16)}...</code> ·
              algorithm <code>{@key.algorithm}</code> ·
              last seen {format_dt(@key.last_seen_at)}
            </p>
          </div>
        </div>

        <div class="ck-card">
          <h2>Event counts</h2>
          <ul class="ck-stat-grid">
            <%= for {kind, n} <- Enum.sort_by(@counts, fn {_k, v} -> -v end) do %>
              <li><strong>{n}</strong> <span>{kind}</span></li>
            <% end %>
          </ul>
        </div>

        <div class="ck-card">
          <h2>Recent events</h2>
          <%= if @events == [] do %>
            <p class="ck-note">No events received yet for this workspace.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Received</th>
                  <th>Kind</th>
                  <th>Event ID</th>
                  <th>Redaction</th>
                </tr>
              </thead>
              <tbody>
                <%= for event <- @events do %>
                  <tr>
                    <td>{format_dt(event.received_at)}</td>
                    <td><code>{event.kind}</code></td>
                    <td><code>{String.slice(event.event_id, 0, 16)}</code></td>
                    <td><code>{event.redaction_policy_version}</code></td>
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

  def render(%{live_action: :show, state: :forbidden} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <h1 class="ck-section-title">Not visible</h1>
        <p class="ck-lead">
          This workspace is enrolled under a different org. Sign in to that org's
          control plane to view its telemetry.
        </p>
      </section>
    </Layouts.app>
    """
  end

  def render(%{live_action: :show, state: :not_found} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <h1 class="ck-section-title">Workspace not found</h1>
        <p class="ck-lead">
          No registration matches that workspace ID. The workspace may have been
          revoked, or it never enrolled with this control plane.
        </p>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="cloud-projects-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Cloud</p>
            <h1 class="ck-section-title">Projects</h1>
            <p class="ck-lead ck-lead-tight">
              Enrolled workspaces visible to your org. Each row is a laptop or
              project that ran <code>controlkeel cloud connect --enroll</code>
              against this control plane.
            </p>
          </div>
        </div>

        {render_body(assigns)}
      </section>
    </Layouts.app>
    """
  end

  defp render_body(%{state: :signed_out} = assigns) do
    ~H"""
    <div class="ck-card">
      <p>
        Sign in via your org's SSO provider to see enrolled workspaces.
        <.link href={~p"/auth/oidc/start"}>Start OIDC login</.link>.
      </p>
    </div>
    """
  end

  defp render_body(%{state: :no_membership} = assigns) do
    ~H"""
    <div class="ck-card">
      <p>
        Your account is signed in but has no active org membership. Ask an org
        owner to invite you, then accept the invitation from
        <code>/cloud/invitations/&lt;token&gt;</code>.
      </p>
    </div>
    """
  end

  defp render_body(%{state: :empty} = assigns) do
    ~H"""
    <div class="ck-card">
      <p>
        No workspaces have enrolled with this org yet. From any project, run:
      </p>
      <pre><code>controlkeel cloud connect --enroll https://controlkeel.com --invite &lt;token&gt;</code></pre>
    </div>
    """
  end

  defp render_body(%{state: :ready} = assigns) do
    ~H"""
    <div class="ck-card">
      <table class="ck-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Workspace ID</th>
            <th>Fingerprint</th>
            <th>Last seen</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <%= for key <- @keys do %>
            <tr>
              <td>{key.name || "—"}</td>
              <td><code>{key.workspace_id}</code></td>
              <td><code>{String.slice(key.fingerprint, 0, 16)}</code></td>
              <td>{format_dt(key.last_seen_at)}</td>
              <td>
                <.link navigate={~p"/cloud/projects/#{key.workspace_id}"}>view</.link>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end

  defp render_body(assigns), do: ~H""

  defp format_dt(nil), do: "never"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
end
