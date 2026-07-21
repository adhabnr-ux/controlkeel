defmodule ControlKeelWeb.OrgSettingsLive do
  @moduledoc """
  Combined org settings at `/organizations/:slug/settings`.

  Sections:
    - General: name, status, budget (owner-only fields)
    - Authentication: OIDC / SAML IdP configuration
    - Security: sign out everywhere (owner-only)

  ## Access

  Resolved per-URL via `Accounts.get_active_membership(user.id, org.id)`
  (NOT the session's pinned `current_membership`). Local mode has no
  membership table and is unrestricted. Cloud/self_hosted requires the
  signed-in user to hold an active admin+ membership for this specific
  org; others are redirected to `/organizations`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Accounts.get_org_by_slug(slug) do
      nil ->
        {:ok, redirect_with_flash(socket, :error, "Organization not found.", ~p"/organizations")}

      org ->
        mode = Mode.current()
        user = socket.assigns[:current_user]

        cond do
          mode == :local ->
            mount_ok(socket, org, true)

          is_nil(user) ->
            {:ok,
             redirect_with_flash(
               socket,
               :error,
               "Sign in to view this organization.",
               ~p"/auth/login"
             )}

          true ->
            case Accounts.get_active_membership(user.id, org.id) do
              nil ->
                {:ok,
                 redirect_with_flash(
                   socket,
                   :error,
                   "You're not a member of that organization.",
                   ~p"/organizations"
                 )}

              membership ->
                if Accounts.role_at_least?(membership.role, "admin") do
                  mount_ok(socket, org, membership.role == "owner")
                else
                  {:ok,
                   redirect_with_flash(
                     socket,
                     :error,
                     "Admin or owner role required.",
                     ~p"/organizations"
                   )}
                end
            end
        end
    end
  end

  defp mount_ok(socket, org, is_owner) do
    idp = Accounts.get_org_identity_provider(org) || %{}
    budget_cents = Accounts.org_budget_cents(org) || 0

    {:ok,
     socket
     |> assign(:page_title, "Settings — #{org.name}")
     |> assign(:org, org)
     |> assign(:is_owner, is_owner)
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
     |> assign(:error, nil)
     |> assign(:idp, idp)
     |> assign(:idp_type, Map.get(idp, "type") || "oidc")
     |> assign(:idp_form, to_form(idp_to_form_params(idp), as: :idp))
     |> assign(:idp_error, nil)
     |> assign(:idp_saved, false)}
  end

  # ── General settings events ────────────────────────────────────────

  @impl true
  def handle_event("submit_settings", %{"settings" => params}, socket) do
    org = socket.assigns.org
    is_owner = socket.assigns.is_owner

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

  # ── Auth / IdP events ──────────────────────────────────────────────

  def handle_event("change-type", %{"idp" => %{"type" => type}}, socket) do
    {:noreply, assign(socket, :idp_type, type)}
  end

  def handle_event("submit_idp", %{"idp" => params}, socket) do
    attrs = normalize_idp(params)

    case Accounts.set_org_identity_provider(socket.assigns.org.id, attrs) do
      {:ok, org} ->
        idp = Accounts.get_org_identity_provider(org) || %{}

        {:noreply,
         socket
         |> assign(:org, org)
         |> assign(:idp, idp)
         |> assign(:idp_saved, true)
         |> assign(:idp_error, nil)
         |> put_flash(:info, "Identity provider saved.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:idp_error, format_idp_error(reason))
         |> assign(:idp_saved, false)}
    end
  end

  def handle_event("clear_idp", _params, socket) do
    case Accounts.set_org_identity_provider(socket.assigns.org.id, nil) do
      {:ok, org} ->
        {:noreply,
         socket
         |> assign(:org, org)
         |> assign(:idp, %{})
         |> assign(:idp_form, to_form(%{}, as: :idp))
         |> assign(:idp_saved, true)
         |> put_flash(:info, "Identity provider cleared.")}

      {:error, reason} ->
        {:noreply, assign(socket, :idp_error, format_idp_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 md:py-12">
      <div class="mb-6 flex items-center justify-between gap-4">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
            {@org.name}
          </p>
          <h1 class="mt-2 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Settings
          </h1>
          <p class="mt-2 text-sm text-zinc-400">
            Slug <code>{@org.slug}</code> cannot be changed — it's bound to your sign-in URL.
          </p>
        </div>

        <.link
          navigate={~p"/organizations/#{@org.slug}"}
          class="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-sm font-medium text-zinc-300 transition hover:bg-white/[0.08] hover:text-white"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Back to members
        </.link>
      </div>

      <%!-- General settings --%>
      <section class="rounded-3xl border border-white/10 bg-zinc-900/70 p-6 shadow-2xl shadow-black/20 backdrop-blur">
        <h2 class="mb-4 text-lg font-semibold text-white">General</h2>
        <.form for={@form} phx-submit="submit_settings" class="flex flex-col gap-4">
          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Organization name</label>
            <input
              type="text"
              name="settings[name]"
              value={@form[:name].value}
              required
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Status</label>
            <select
              name="settings[status]"
              disabled={not @is_owner}
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
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
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
            />
            <%= unless @is_owner do %>
              <p class="mt-1 text-xs text-zinc-500">Only owners can change budget.</p>
            <% end %>
          </div>

          <%= if @error do %>
            <p class="rounded-lg bg-red-500/10 px-3 py-2 text-sm text-red-300">{@error}</p>
          <% end %>
          <%= if @saved do %>
            <p class="rounded-lg bg-emerald-500/10 px-3 py-2 text-sm text-emerald-300">Saved.</p>
          <% end %>

          <button
            type="submit"
            class="inline-flex items-center gap-2 self-start rounded-full bg-lime-300 px-5 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
          >
            Save
          </button>
        </.form>
      </section>

      <%!-- Authentication / IdP settings --%>
      <section class="mt-8 rounded-3xl border border-white/10 bg-zinc-900/70 p-6 shadow-2xl shadow-black/20 backdrop-blur">
        <h2 class="mb-2 text-lg font-semibold text-white">Authentication</h2>
        <p class="mb-4 text-sm text-zinc-400">
          Configure the identity provider members use to sign in via <code>/auth/login</code>.
        </p>

        <.form
          for={@idp_form}
          phx-submit="submit_idp"
          phx-change="change-type"
          class="flex flex-col gap-4"
        >
          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Provider type</label>
            <select
              name="idp[type]"
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
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
                class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Client ID</label>
              <input
                type="text"
                name="idp[client_id]"
                value={Map.get(@idp, "client_id", "")}
                required
                class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Client secret</label>
              <input
                type="password"
                name="idp[client_secret]"
                value={Map.get(@idp, "client_secret", "")}
                class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
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
                class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">IdP metadata URL</label>
              <input
                type="text"
                name="idp[idp_metadata_url]"
                value={Map.get(@idp, "idp_metadata_url", "")}
                required
                class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
              />
            </div>
          <% end %>

          <%= if @idp_error do %>
            <p class="rounded-lg bg-red-500/10 px-3 py-2 text-sm text-red-300">{@idp_error}</p>
          <% end %>
          <%= if @idp_saved do %>
            <p class="rounded-lg bg-emerald-500/10 px-3 py-2 text-sm text-emerald-300">
              Settings saved. Test sign-in at <code>/auth/login</code>
              with org slug <code>{@org.slug}</code>.
            </p>
          <% end %>

          <div class="flex gap-2">
            <button
              type="submit"
              class="inline-flex items-center gap-2 rounded-full bg-lime-300 px-5 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
            >
              Save
            </button>
            <%= if @idp != %{} do %>
              <button
                type="button"
                phx-click="clear_idp"
                class="rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-sm font-medium text-zinc-300 transition hover:bg-white/[0.08] hover:text-white"
              >
                Clear
              </button>
            <% end %>
          </div>
        </.form>
      </section>
    </section>
    """
  end

  # ── Private helpers ────────────────────────────────────────────────

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

  defp idp_to_form_params(idp) when is_map(idp) do
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

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
