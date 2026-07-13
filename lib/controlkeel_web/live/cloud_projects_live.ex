defmodule ControlKeelWeb.CloudProjectsLive do
  @moduledoc """
  Org-scoped list of enrolled workspaces and per-workspace event detail view.

  Phase 7 (multi-tenant SaaS) acceptance gate: an SSO'd user can land on
  `/cloud/projects`, see the workspaces enrolled under their org, click into
  one, and read the recent telemetry events that workspace has posted.

  Authorization:

    - `:index` requires an active org membership; the org_id pins the list.
    - `:show` resolves the requested workspace_id through
      `KeyRegistry.fetch/1`, then enforces that `key.org_id` matches
      the SSO'd org. Without a session this falls back to the local
      `Identity` for single-node self-host (the unauthenticated
      page still surfaces the receiver's own workspace).

  This LiveView is intentionally read-only — enrolment happens through the
  CLI (`controlkeel cloud connect --enroll`), not the web UI.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Cloud.Telemetry.Ingestion
  alias ControlKeel.Cloud.RuntimeContext
  alias ControlKeel.Cloud.Workspace.Key
  alias ControlKeel.Cloud.Workspace.KeyRegistry
  alias ControlKeel.Mission
  alias ControlKeel.Repo

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
          socket.assigns.current_org_id
          |> KeyRegistry.list_for_org()
          |> Repo.preload(:mission_workspace)

        true ->
          []
      end

    {:ok,
     socket
     |> assign(:keys, keys)
     |> assign(:state, list_state(socket, keys))
     |> assign(:show_create_form, false)
     |> assign(:create_form, to_form(empty_workspace_params(), as: :workspace))
     |> assign(:create_error, nil)}
  end

  defp empty_workspace_params do
    %{
      "name" => "",
      "slug" => "",
      "industry" => "software",
      "agent" => "claude-code",
      "budget_cents" => "10000",
      "compliance_profile" => "baseline"
    }
  end

  defp mount_show(%{"ws_id" => ws_id}, socket) do
    case KeyRegistry.fetch(ws_id) do
      {:ok, key} ->
        key = Repo.preload(key, :mission_workspace)

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

  defp assign_show_state(socket, %Key{} = key) do
    events = Ingestion.recent_for_workspace(key.workspace_id, limit: 50)
    counts = Ingestion.counts_for_workspace(key.workspace_id)
    packages = list_packages(key)

    socket
    |> assign(:state, :show)
    |> assign(:key, key)
    |> assign(:events, events)
    |> assign(:counts, counts)
    |> assign(:packages, packages)
  end

  defp list_packages(%Key{mission_workspace_id: nil}), do: []

  defp list_packages(%Key{mission_workspace_id: mws_id}) when is_integer(mws_id) do
    RuntimeContext.list_for_workspace(mws_id, limit: 25)
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
            %Key{} = key -> assign_show_state(socket, key)
            _ -> socket
          end

        _ ->
          keys =
            if socket.assigns.current_membership do
              socket.assigns.current_org_id
              |> KeyRegistry.list_for_org()
              |> Repo.preload(:mission_workspace)
            else
              []
            end

          socket
          |> assign(:keys, keys)
          |> assign(:state, list_state(socket, keys))
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle-create-workspace", _params, socket) do
    {:noreply, assign(socket, :show_create_form, !socket.assigns.show_create_form)}
  end

  def handle_event("create-workspace", %{"workspace" => params}, socket) do
    cond do
      is_nil(socket.assigns.current_membership) ->
        {:noreply, assign(socket, :create_error, "You must be signed in.")}

      not Accounts.role_at_least?(socket.assigns.current_membership.role, "admin") ->
        {:noreply,
         assign(socket, :create_error, "Admin or owner role required to create workspaces.")}

      true ->
        attrs = normalize_workspace_attrs(params, socket.assigns.current_org_id)

        case Mission.create_workspace(attrs) do
          {:ok, workspace} ->
            _ = Accounts.assign_workspace_to_org(workspace.id, socket.assigns.current_org_id)

            keys =
              socket.assigns.current_org_id
              |> KeyRegistry.list_for_org()
              |> Repo.preload(:mission_workspace)

            {:noreply,
             socket
             |> assign(:keys, keys)
             |> assign(:state, list_state(socket, keys))
             |> assign(:show_create_form, false)
             |> assign(:create_form, to_form(empty_workspace_params(), as: :workspace))
             |> assign(:create_error, nil)
             |> put_flash(:info, "Workspace \"#{workspace.name}\" created.")}

          {:error, %Ecto.Changeset{} = cs} ->
            errors =
              cs.errors
              |> Enum.map_join("; ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)

            {:noreply,
             socket
             |> assign(:create_form, to_form(params, as: :workspace))
             |> assign(:create_error, errors)}
        end
    end
  end

  defp normalize_workspace_attrs(params, org_id) do
    %{
      name: params["name"],
      slug: params["slug"],
      industry: params["industry"] || "software",
      agent: params["agent"] || "claude-code",
      budget_cents: parse_budget(params["budget_cents"]),
      compliance_profile: params["compliance_profile"] || "baseline",
      status: "active",
      org_id: org_id
    }
  end

  defp parse_budget(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> n
      _ -> 10_000
    end
  end

  defp parse_budget(value) when is_integer(value) and value >= 0, do: value
  defp parse_budget(_), do: 10_000

  @impl true
  def render(%{live_action: :show, state: :show} = assigns) do
    ~H"""
    <section id="cloud-project-page" class="ck-shell ck-shell-tight">
      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">
            <.link navigate={~p"/cloud/projects"}>Cloud projects</.link>
            / <code>{@key.workspace_id}</code>
          </p>
          <h1 class="ck-section-title">{@key.name || @key.workspace_id}</h1>
          <p class="ck-lead ck-lead-tight">
            <span :if={@key.mission_workspace}>
              Project: <strong>{@key.mission_workspace.slug}</strong> ·
            </span>
            Fingerprint <code>{String.slice(@key.fingerprint, 0, 16)}...</code>
            ·
            algorithm <code>{@key.algorithm}</code>
            ·
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
        <h2>Cloud run packages</h2>
        <%= cond do %>
          <% is_nil(@key.mission_workspace_id) -> %>
            <p class="ck-note">
              This enrolled workspace is not yet linked to a project. Issue a scoped invite from the org to link it.
            </p>
          <% @packages == [] -> %>
            <p class="ck-note">No cloud runs handed off yet.</p>
          <% true -> %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Package</th>
                  <th>Runtime</th>
                  <th>Status</th>
                  <th>Revision</th>
                  <th>Budget</th>
                  <th>Started</th>
                  <th>Finished</th>
                </tr>
              </thead>
              <tbody>
                <%= for pkg <- @packages do %>
                  <tr>
                    <td><code>{pkg.external_id}</code></td>
                    <td><code>{pkg.runtime_target}</code></td>
                    <td>
                      <span class={"ck-badge ck-badge-#{package_status_class(pkg.status)}"}>
                        {pkg.status}
                      </span>
                    </td>
                    <td>{format_revision(pkg)}</td>
                    <td>{pkg.budget_cents_allocated}¢</td>
                    <td>{format_dt(pkg.dispatched_at)}</td>
                    <td>{format_dt(pkg.completed_at)}</td>
                  </tr>
                <% end %>
              </tbody>
            </table>
        <% end %>
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
    """
  end

  def render(%{live_action: :show, state: :forbidden} = assigns) do
    ~H"""
    <section class="ck-shell ck-shell-tight">
      <h1 class="ck-section-title">Not visible</h1>
      <p class="ck-lead">
        This workspace is enrolled under a different org. Sign in to that org's
        control plane to view its telemetry.
      </p>
    </section>
    """
  end

  def render(%{live_action: :show, state: :not_found} = assigns) do
    ~H"""
    <section class="ck-shell ck-shell-tight">
      <h1 class="ck-section-title">Workspace not found</h1>
      <p class="ck-lead">
        No registration matches that workspace ID. The workspace may have been
        revoked, or it never enrolled with this control plane.
      </p>
    </section>
    """
  end

  def render(assigns) do
    ~H"""
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
    """
  end

  defp render_body(%{state: :signed_out} = assigns) do
    ~H"""
    <div class="ck-card">
      <p>
        Sign in via your org's SSO provider to see enrolled workspaces. <.link href={
          ~p"/auth/oidc/start"
        }>Start OIDC login</.link>.
      </p>
    </div>
    """
  end

  defp render_body(%{state: :no_membership} = assigns) do
    ~H"""
    <div class="ck-card">
      <p>
        Your account is signed in but has no active org membership. Ask an org
        owner to invite you, then accept the invitation from <code>/cloud/invitations/&lt;token&gt;</code>.
      </p>
    </div>
    """
  end

  defp render_body(%{state: :empty} = assigns) do
    ~H"""
    <div class="ck-card">
      <p>
        No workspaces have enrolled with this org yet. Create one below, or from any project run:
      </p>
      <pre><code>controlkeel cloud connect --enroll https://controlkeel.com --invite &lt;token&gt;</code></pre>
    </div>
    {render_create_workspace(assigns)}
    """
  end

  defp render_body(%{state: :ready} = assigns) do
    ~H"""
    {render_create_workspace(assigns)}
    <div class="ck-card">
      <table class="ck-table">
        <thead>
          <tr>
            <th>Name</th>
            <th>Project</th>
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
              <td>{project_label(key)}</td>
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

  defp render_create_workspace(assigns) do
    can_create =
      assigns.current_membership &&
        ControlKeel.Accounts.role_at_least?(assigns.current_membership.role, "admin")

    assigns = Map.put(assigns, :can_create, can_create)

    ~H"""
    <%= if @can_create do %>
      <div class="ck-card" id="create-workspace-section">
        <%= if @show_create_form do %>
          <h3 class="ck-section-subtitle">New workspace</h3>
          <.form for={@create_form} phx-submit="create-workspace" class="flex flex-col gap-3">
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Name</label>
              <input
                type="text"
                name="workspace[name]"
                value={@create_form[:name].value || ""}
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Slug</label>
              <input
                type="text"
                name="workspace[slug]"
                value={@create_form[:slug].value || ""}
                required
                pattern="[a-z0-9][a-z0-9\-]*"
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">Industry</label>
                <input
                  type="text"
                  name="workspace[industry]"
                  value={@create_form[:industry].value || "software"}
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">Agent</label>
                <input
                  type="text"
                  name="workspace[agent]"
                  value={@create_form[:agent].value || "claude-code"}
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">
                  Monthly budget (cents)
                </label>
                <input
                  type="number"
                  name="workspace[budget_cents]"
                  value={@create_form[:budget_cents].value || "10000"}
                  min="0"
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">Compliance profile</label>
                <input
                  type="text"
                  name="workspace[compliance_profile]"
                  value={@create_form[:compliance_profile].value || "baseline"}
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
            </div>
            <%= if @create_error do %>
              <p class="ck-note ck-note-danger">{@create_error}</p>
            <% end %>
            <div class="flex gap-2">
              <button type="submit" class="ck-btn ck-btn-primary">Create workspace</button>
              <button
                type="button"
                phx-click="toggle-create-workspace"
                class="ck-btn ck-btn-secondary"
              >
                Cancel
              </button>
            </div>
          </.form>
        <% else %>
          <button type="button" phx-click="toggle-create-workspace" class="ck-btn ck-btn-primary">
            + Create workspace
          </button>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp format_dt(nil), do: "never"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp project_label(%Key{mission_workspace: %{slug: slug}}) when is_binary(slug),
    do: slug

  defp project_label(_), do: "—"

  defp package_status_class("completed"), do: "ok"
  defp package_status_class("failed"), do: "error"
  defp package_status_class("cancelled"), do: "muted"
  defp package_status_class("in_progress"), do: "active"
  defp package_status_class("dispatched"), do: "active"
  defp package_status_class(_), do: "neutral"

  defp format_revision(%{branch: nil, commit_sha: nil}), do: "—"

  defp format_revision(%{branch: branch, commit_sha: nil}) when is_binary(branch), do: branch

  defp format_revision(%{branch: nil, commit_sha: sha}) when is_binary(sha),
    do: short_sha(sha)

  defp format_revision(%{branch: branch, commit_sha: sha})
       when is_binary(branch) and is_binary(sha),
       do: "#{branch}@#{short_sha(sha)}"

  defp format_revision(_), do: "—"

  defp short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 7)
end
