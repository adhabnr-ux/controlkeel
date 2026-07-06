defmodule ControlKeelWeb.WorkspaceWebhooksLive do
  @moduledoc """
  Outbound integration webhooks for a workspace at `/workspaces/:id/webhooks`.

  Admin+owner can list, create, and replay webhooks. The webhook secret
  is shown once at creation; the DB stores the plaintext for HMAC signing
  on emit (operators see it once via the create banner).

  Cross-org access is rejected at mount.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Platform
  alias ControlKeel.Platform.IntegrationWebhook
  alias ControlKeel.Repo

  @impl true
  def mount(%{"id" => ws_id_param}, _session, socket) do
    with {ws_id, ""} <- Integer.parse(ws_id_param),
         %Workspace{} = workspace <- Repo.get(Workspace, ws_id),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      {:ok,
       socket
       |> assign(:page_title, "Webhooks — #{workspace.name}")
       |> assign(:workspace, workspace)
       |> assign(:webhooks, Platform.list_webhooks(workspace.id))
       |> assign(:available_events, Platform.webhook_events())
       |> assign(:new_secret, nil)
       |> assign(:new_secret_for, nil)
       |> assign(:create_form, to_form(%{"name" => "", "url" => ""}, as: :wh))
       |> assign(:create_error, nil)}
    else
      :error ->
        {:ok, redirect_with_flash(socket, :error, "Invalid workspace id.", ~p"/cloud/projects")}

      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/cloud/projects")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/cloud/projects")}
    end
  end

  @impl true
  def handle_event("create", %{"wh" => params} = full_params, socket) do
    name = params["name"] |> to_string() |> String.trim()
    url = params["url"] |> to_string() |> String.trim()
    events = extract_events(full_params)

    cond do
      name == "" or url == "" ->
        {:noreply, assign(socket, :create_error, "Name and URL are required.")}

      true ->
        attrs = %{
          "name" => name,
          "url" => url,
          "subscribed_events" => events
        }

        case Platform.create_webhook(socket.assigns.workspace.id, attrs) do
          {:ok, webhook} ->
            {:noreply,
             socket
             |> assign(:webhooks, Platform.list_webhooks(socket.assigns.workspace.id))
             |> assign(:new_secret, webhook.secret)
             |> assign(:new_secret_for, webhook.name)
             |> assign(:create_form, to_form(%{"name" => "", "url" => ""}, as: :wh))
             |> assign(:create_error, nil)
             |> put_flash(:info, "Webhook #{webhook.name} created.")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply,
             assign(
               socket,
               :create_error,
               Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
             )}
        end
    end
  end

  def handle_event("replay", %{"id" => id}, socket) do
    with {wh_id, ""} <- Integer.parse(id),
         {:ok, _} <- Platform.replay_webhook(wh_id) do
      {:noreply, put_flash(socket, :info, "Webhook replayed.")}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "No prior delivery to replay for this webhook.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not replay webhook.")}
    end
  end

  def handle_event("dismiss-secret", _, socket) do
    {:noreply, assign(socket, :new_secret, nil) |> assign(:new_secret_for, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section class="ck-shell" style="max-width: 920px; margin: 4rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">{@workspace.name}</p>
            <h1 class="ck-section-title">Webhooks</h1>
            <p class="ck-lead ck-lead-tight">
              Subscribe external systems to ControlKeel events. Each webhook gets a server-generated secret used to sign payloads.
            </p>
          </div>
        </div>

        <%= if @new_secret do %>
          <div
            class="ck-card mt-6"
            id="new-secret-banner"
            style="border-color: rgba(190, 242, 100, 0.4);"
          >
            <p>
              <strong>Signing secret for {@new_secret_for}.</strong>
              Copy now — it will not be shown again.
            </p>
            <pre><code id="new-secret-value">{@new_secret}</code></pre>
            <button type="button" phx-click="dismiss-secret" class="ck-btn ck-btn-secondary">
              Dismiss
            </button>
          </div>
        <% end %>

        <div class="ck-card mt-6">
          <h2 class="ck-section-subtitle">Create webhook</h2>
          <.form for={@create_form} phx-submit="create" class="flex flex-col gap-3">
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Name</label>
              <input
                type="text"
                name="wh[name]"
                value={@create_form[:name].value || ""}
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Delivery URL</label>
              <input
                type="url"
                name="wh[url]"
                value={@create_form[:url].value || ""}
                required
                placeholder="https://example.com/hooks/controlkeel"
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-2">Events</label>
              <div class="grid grid-cols-2 gap-2">
                <%= for ev <- @available_events do %>
                  <label class="flex items-center gap-2 text-sm text-zinc-300">
                    <input type="checkbox" name="events[]" value={ev} />
                    <code>{ev}</code>
                  </label>
                <% end %>
              </div>
            </div>
            <%= if @create_error do %>
              <p class="ck-note ck-note-danger">{@create_error}</p>
            <% end %>
            <button type="submit" class="ck-btn ck-btn-primary self-start">Create webhook</button>
          </.form>
        </div>

        <div class="ck-card mt-6">
          <h2 class="ck-section-subtitle">Configured webhooks</h2>
          <%= if @webhooks == [] do %>
            <p class="ck-lead-tight">No webhooks configured yet.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>URL</th>
                  <th>Events</th>
                  <th>Status</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for w <- @webhooks do %>
                  <tr id={"webhook-#{w.id}"}>
                    <td>{w.name}</td>
                    <td><code>{w.url}</code></td>
                    <td><code>{IntegrationWebhook.event_list(w) |> Enum.join(", ")}</code></td>
                    <td>{w.status}</td>
                    <td>
                      <button
                        type="button"
                        phx-click="replay"
                        phx-value-id={w.id}
                        class="ck-btn ck-btn-secondary"
                      >
                        Replay last
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  # ── Private ────────────────────────────────────────────────────────

  defp extract_events(%{"events" => events}) when is_list(events) do
    Enum.filter(events, &is_binary/1)
  end

  defp extract_events(_), do: []

  defp check_workspace_access(%Workspace{org_id: nil}, _),
    do: {:error, "Workspace is not bound to an org."}

  defp check_workspace_access(%Workspace{org_id: ws_org}, %{
         current_org_id: org_id,
         current_membership: m
       })
       when is_integer(ws_org) and ws_org == org_id do
    if m && Accounts.role_at_least?(m.role, "admin"),
      do: :ok,
      else: {:error, "Admin or owner role required."}
  end

  defp check_workspace_access(_, _),
    do: {:error, "Workspace belongs to a different organization."}

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
