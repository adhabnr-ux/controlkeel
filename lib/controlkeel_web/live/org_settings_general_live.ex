defmodule ControlKeelWeb.OrgSettingsGeneralLive do
  @moduledoc """
  General org settings at `/org/:slug/settings/general`.

  Owner+admin can edit name. Owner-only can change status and monthly budget.
  Slug is intentionally not editable — it's used in sign-in URLs and changing
  it would break existing OIDC return paths.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Organization not found.", ~p"/cloud/projects")}

      org ->
        membership = socket.assigns[:current_membership]

        cond do
          is_nil(membership) or membership.org_id != org.id ->
            {:ok,
             redirect_with_flash(
               socket,
               :error,
               "You're not a member of that organization.",
               ~p"/cloud/projects"
             )}

          not Accounts.role_at_least?(membership.role, "admin") ->
            {:ok,
             redirect_with_flash(
               socket,
               :error,
               "Admin or owner role required.",
               ~p"/cloud/projects"
             )}

          true ->
            budget_cents = Accounts.org_budget_cents(org) || 0

            {:ok,
             socket
             |> assign(:page_title, "Settings — #{org.name}")
             |> assign(:org, org)
             |> assign(:is_owner, membership.role == "owner")
             |> assign(
               :form,
               to_form(
                 %{
                   "name" => org.name,
                   "status" => org.status,
                   "budget_cents" => Integer.to_string(budget_cents)
                 },
                 as: :settings
               )
             )
             |> assign(:saved, false)
             |> assign(:error, nil)}
        end
    end
  end

  @impl true
  def handle_event("submit", %{"settings" => params}, socket) do
    org = socket.assigns.org
    is_owner = socket.assigns.is_owner

    # Admins can change name. Only owners can change status/budget.
    org_attrs =
      %{name: params["name"]}
      |> maybe_add_owner_field("status", params["status"], is_owner)

    with {:ok, org} <- Accounts.update_org(org, org_attrs),
         {:ok, org} <- maybe_set_budget(org, params["budget_cents"], is_owner) do
      {:noreply,
       socket
       |> assign(:org, org)
       |> assign(:saved, true)
       |> assign(:error, nil)
       |> put_flash(:info, "Settings saved.")}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        msg =
          cs.errors
          |> Enum.map_join(", ", fn {f, {m, _}} -> "#{f}: #{m}" end)

        {:noreply, assign(socket, :error, msg) |> assign(:saved, false)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, inspect(reason)) |> assign(:saved, false)}
    end
  end

  @impl true
  def handle_event("sign_out_everywhere", _params, socket) do
    if socket.assigns[:current_user] do
      Accounts.sign_out_everywhere(socket.assigns.current_user.id)
      {:noreply, put_flash(socket, :info, "All other sessions have been signed out.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 640px; margin: 4rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">{@org.name}</p>
            <h1 class="ck-section-title">General settings</h1>
            <p class="ck-lead ck-lead-tight">
              Slug <code>{@org.slug}</code> cannot be changed — it's bound to your sign-in URL.
            </p>
          </div>
          <div>
            <.link navigate={~p"/org/#{@org.slug}/members"} class="ck-btn ck-btn-secondary">
              Members
            </.link>
          </div>
        </div>

        <.form for={@form} phx-submit="submit" class="ck-card mt-6 flex flex-col gap-4">
          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Organization name</label>
            <input
              type="text"
              name="settings[name]"
              value={@form[:name].value}
              required
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Status</label>
            <select
              name="settings[status]"
              disabled={not @is_owner}
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
            >
              <option value="active" selected={@form[:status].value == "active"}>active</option>
              <option value="disabled" selected={@form[:status].value == "disabled"}>disabled</option>
            </select>
            <%= unless @is_owner do %>
              <p class="mt-1 text-xs text-zinc-500">Only owners can change status.</p>
            <% end %>
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Monthly budget (cents)</label>
            <input
              type="number"
              name="settings[budget_cents]"
              value={@form[:budget_cents].value || "0"}
              min="0"
              disabled={not @is_owner}
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
            />
            <%= unless @is_owner do %>
              <p class="mt-1 text-xs text-zinc-500">Only owners can change budget.</p>
            <% end %>
          </div>

          <%= if @error do %>
            <p class="ck-note ck-note-danger">{@error}</p>
          <% end %>

          <%= if @saved do %>
            <p class="ck-note ck-note-success">Saved.</p>
          <% end %>

          <button type="submit" class="ck-btn ck-btn-primary self-start">Save</button>
        </.form>

        <%= if @is_owner do %>
          <div class="ck-card mt-8">
            <h2 class="text-lg font-semibold text-zinc-100 mb-2">Security</h2>
            <p class="text-sm text-zinc-400 mb-4">
              Sign out from all active browser sessions. You will stay signed in on this device.
            </p>
            <button
              type="button"
              phx-click="sign_out_everywhere"
              data-confirm="This will sign out all other active sessions. Continue?"
              class="ck-btn ck-btn-secondary"
            >
              Sign out everywhere
            </button>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  # ── Private ────────────────────────────────────────────────────────

  defp maybe_add_owner_field(attrs, _key, _value, false), do: attrs
  defp maybe_add_owner_field(attrs, _key, nil, _is_owner), do: attrs

  defp maybe_add_owner_field(attrs, key, value, true),
    do: Map.put(attrs, String.to_existing_atom(key), value)

  defp maybe_set_budget(org, _value, false), do: {:ok, org}
  defp maybe_set_budget(org, nil, _), do: {:ok, org}

  defp maybe_set_budget(org, value, true) when is_binary(value) do
    case Integer.parse(value) do
      {cents, ""} when cents >= 0 ->
        case Accounts.set_org_budget_cents(org.id, cents) do
          {:ok, updated} -> {:ok, updated}
          {:error, _} = err -> err
        end

      _ ->
        {:error, "Budget must be a non-negative integer (in cents)."}
    end
  end

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
