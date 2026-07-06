defmodule ControlKeelWeb.OrgSettingsAuthLive do
  @moduledoc """
  IdP configuration for an org at `/org/:slug/settings/auth`.

  Org owners and admins configure the OIDC issuer/client_id/client_secret
  (or SAML entity_id/idp_metadata_url) that powers `/auth/login` for their
  workspace.

  ## Access

  Only members with role `admin` or higher can view or modify this page.
  Other members are redirected to `/cloud/projects`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Organization not found.")
         |> push_navigate(to: ~p"/cloud/projects")}

      org ->
        membership = socket.assigns[:current_membership]

        cond do
          is_nil(membership) or membership.org_id != org.id ->
            {:ok,
             socket
             |> put_flash(:error, "You're not a member of that organization.")
             |> push_navigate(to: ~p"/cloud/projects")}

          not Accounts.role_at_least?(membership.role, "admin") ->
            {:ok,
             socket
             |> put_flash(:error, "Admin or owner role required.")
             |> push_navigate(to: ~p"/cloud/projects")}

          true ->
            idp = Accounts.get_org_identity_provider(org) || %{}

            {:ok,
             socket
             |> assign(:page_title, "Authentication — #{org.name}")
             |> assign(:org, org)
             |> assign(:idp, idp)
             |> assign(:idp_type, Map.get(idp, "type") || "oidc")
             |> assign(:form, to_form(idp_to_form_params(idp), as: :idp))
             |> assign(:error, nil)
             |> assign(:saved, false)}
        end
    end
  end

  @impl true
  def handle_event("change-type", %{"idp" => %{"type" => type}}, socket) do
    {:noreply, assign(socket, :idp_type, type)}
  end

  def handle_event("submit", %{"idp" => params}, socket) do
    attrs = normalize_idp(params)

    case Accounts.set_org_identity_provider(socket.assigns.org.id, attrs) do
      {:ok, org} ->
        idp = Accounts.get_org_identity_provider(org) || %{}

        {:noreply,
         socket
         |> assign(:org, org)
         |> assign(:idp, idp)
         |> assign(:saved, true)
         |> assign(:error, nil)
         |> put_flash(:info, "Identity provider saved.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, format_idp_error(reason))
         |> assign(:saved, false)}
    end
  end

  def handle_event("clear", _params, socket) do
    case Accounts.set_org_identity_provider(socket.assigns.org.id, nil) do
      {:ok, org} ->
        {:noreply,
         socket
         |> assign(:org, org)
         |> assign(:idp, %{})
         |> assign(:form, to_form(%{}, as: :idp))
         |> assign(:saved, true)
         |> put_flash(:info, "Identity provider cleared.")}

      {:error, reason} ->
        {:noreply, assign(socket, :error, format_idp_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section class="ck-shell" style="max-width: 720px; margin: 4rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">{@org.name}</p>
            <h1 class="ck-section-title">Authentication</h1>
            <p class="ck-lead ck-lead-tight">
              Configure the identity provider members use to sign in via <code>/auth/login</code>.
            </p>
          </div>
        </div>

        <.form
          for={@form}
          phx-submit="submit"
          phx-change="change-type"
          class="ck-card mt-6 flex flex-col gap-4"
        >
          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Provider type</label>
            <select
              name="idp[type]"
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
            >
              <option value="oidc" selected={@idp_type == "oidc"}>OIDC</option>
              <option value="saml" selected={@idp_type == "saml"}>SAML</option>
            </select>
          </div>

          <%= if @idp_type == "oidc" do %>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Issuer</label>
              <input
                type="text"
                name="idp[issuer]"
                value={Map.get(@idp, "issuer", "")}
                placeholder="https://accounts.google.com"
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Client ID</label>
              <input
                type="text"
                name="idp[client_id]"
                value={Map.get(@idp, "client_id", "")}
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Client secret</label>
              <input
                type="password"
                name="idp[client_secret]"
                value={Map.get(@idp, "client_secret", "")}
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
              <p class="mt-1 text-xs text-zinc-500">Leave blank to keep the existing secret.</p>
            </div>
          <% else %>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Entity ID</label>
              <input
                type="text"
                name="idp[entity_id]"
                value={Map.get(@idp, "entity_id", "")}
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">IdP metadata URL</label>
              <input
                type="text"
                name="idp[idp_metadata_url]"
                value={Map.get(@idp, "idp_metadata_url", "")}
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>
          <% end %>

          <%= if @error do %>
            <p class="ck-note ck-note-danger">{@error}</p>
          <% end %>
          <%= if @saved do %>
            <p class="ck-note ck-note-success">
              Settings saved. Test sign-in at <code>/auth/login</code>
              with org slug <code>{@org.slug}</code>.
            </p>
          <% end %>

          <div class="flex gap-2">
            <button type="submit" class="ck-btn ck-btn-primary">Save</button>
            <%= if @idp != %{} do %>
              <button type="button" phx-click="clear" class="ck-btn ck-btn-secondary">Clear</button>
            <% end %>
          </div>
        </.form>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  # ── Private ────────────────────────────────────────────────────────

  defp idp_to_form_params(idp) when is_map(idp) do
    # Keep secrets out of the form (they should be re-entered if changed)
    Map.drop(idp, ["client_secret"])
  end

  defp normalize_idp(params) do
    type = params["type"] || "oidc"
    base = %{"type" => type}

    case type do
      "oidc" ->
        base
        |> maybe_put("issuer", params["issuer"])
        |> maybe_put("client_id", params["client_id"])
        |> maybe_put("client_secret", params["client_secret"])

      "saml" ->
        base
        |> maybe_put("entity_id", params["entity_id"])
        |> maybe_put("idp_metadata_url", params["idp_metadata_url"])

      _ ->
        base
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp format_idp_error(:not_found), do: "Organization not found."
  defp format_idp_error(:unsupported_provider_type), do: "Unsupported provider type."

  defp format_idp_error({:missing_fields, fields}),
    do: "Missing required fields: #{Enum.join(fields, ", ")}"

  defp format_idp_error(%Ecto.Changeset{}), do: "Could not save settings."
  defp format_idp_error(other), do: "Error: #{inspect(other)}"
end
