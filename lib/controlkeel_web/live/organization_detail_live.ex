defmodule ControlKeelWeb.OrganizationDetailLive do
  @moduledoc """
  Member management for an org at `/organizations/:slug`.

  Admin+owner only. Allows:
    - List active and pending memberships (preloaded with the user)
    - Invite a new member by email + role (creates pending Membership;
      raw invitation token is displayed once for copy-paste, since the
      real mailer is deferred to P1c)
    - Revoke a membership (last-owner protected)
    - Change a role (last-owner protected)

  ## Access

  Resolved per-URL via `Accounts.get_active_membership(user.id, org.id)`
  (NOT the session's pinned `current_membership`). Local mode has no
  membership table and is unrestricted. Cloud/self_hosted requires the
  signed-in user to hold an active admin+ membership for this specific
  org; others are redirected to `/organizations`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Repo
  alias ControlKeel.Runtime.Mode

  @valid_roles ~w(owner admin member viewer)

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
            mount_ok(socket, org)

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
                mount_ok(socket, org, membership)
            end
        end
    end
  end

  defp mount_ok(socket, org, membership \\ nil) do
    local_mode = Mode.current() == :local
    budget_cents = Accounts.org_budget_cents(org) || 0
    member_count = Accounts.count_memberships_for_org(org.id)
    can_manage = membership && Accounts.role_at_least?(membership.role, "admin")

    {:ok,
     socket
     |> assign(:page_title, "Members — #{org.name}")
     |> assign(:org, org)
     |> assign(:local_mode, local_mode)
     |> assign(:budget_cents, budget_cents)
     |> assign(:member_count, member_count)
     |> assign(:can_manage, can_manage)
     |> assign(:memberships, if(local_mode, do: [], else: load_memberships(org.id)))
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
     |> assign(:invite_token, nil)
     |> assign(:invite_error, nil)
     |> assign(:show_invite_modal, false)
     |> assign(:current_user, socket.assigns[:current_user])}
  end

  @impl true
  def handle_event("open_invite", _params, socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("close_invite", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_invite_modal, false)
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
     |> assign(:invite_error, nil)}
  end

  @impl true
  def handle_event("invite", %{"invite" => %{"email" => raw_email, "role" => role}}, socket) do
    email = raw_email |> to_string() |> String.downcase() |> String.trim()
    role = if role in @valid_roles, do: role, else: "member"

    with :ok <- validate_email(email),
         {:ok, user} <- find_or_create_user(email),
         {:ok, _membership, raw_token} <-
           Accounts.invite_member(user.id, socket.assigns.org.id,
             role: role,
             invited_by_user_id: socket.assigns.current_user.id
           ) do
      # Best-effort email delivery. Token banner remains as visible fallback,
      # so a mailer failure does not block the operator from completing the invite.
      _ = ControlKeel.Mailer.deliver_invitation(%{email: user.email}, raw_token)

      {:noreply,
       socket
       |> assign(:memberships, load_memberships(socket.assigns.org.id))
       |> assign(:member_count, Accounts.count_memberships_for_org(socket.assigns.org.id))
       |> assign(:invite_token, raw_token)
       |> assign(:invite_error, nil)
       |> assign(:show_invite_modal, false)
       |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:invite_error, format_error(reason))
         |> assign(:invite_token, nil)}
    end
  end

  def handle_event("revoke", %{"membership-id" => id}, socket) do
    with {membership_id, ""} <- Integer.parse(id),
         {:ok, _} <- Accounts.revoke_membership(membership_id) do
      {:noreply,
       socket
       |> assign(:memberships, load_memberships(socket.assigns.org.id))
       |> assign(:member_count, Accounts.count_memberships_for_org(socket.assigns.org.id))
       |> put_flash(:info, "Membership revoked.")}
    else
      {:error, :last_owner_protected} ->
        {:noreply,
         put_flash(socket, :error, "Cannot revoke the last owner of this organization.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Membership not found.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not revoke membership.")}
    end
  end

  def handle_event(
        "change-role",
        %{"membership-id" => id, "role" => new_role},
        socket
      ) do
    with {membership_id, ""} <- Integer.parse(id),
         {:ok, _} <- Accounts.update_membership_role(membership_id, new_role) do
      {:noreply,
       socket
       |> assign(:memberships, load_memberships(socket.assigns.org.id))
       |> put_flash(:info, "Role updated.")}
    else
      {:error, :last_owner_protected} ->
        {:noreply,
         put_flash(socket, :error, "Cannot demote the last owner of this organization.")}

      {:error, :invalid_role} ->
        {:noreply, put_flash(socket, :error, "Invalid role.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Membership not found.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not update role.")}
    end
  end

  def handle_event("dismiss-token", _params, socket) do
    {:noreply, assign(socket, :invite_token, nil)}
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
          <%= if @local_mode do %>
            <p class="mt-2 text-sm text-zinc-400">
              View your organization details below. Member management is not available in local mode.
            </p>
          <% else %>
            <p class="mt-2 text-sm text-zinc-400">
              Invite teammates and manage roles. Owners can promote and demote; the last owner is protected.
            </p>
          <% end %>
        </div>

        <div class="flex items-center gap-3">
          <.link
            navigate={~p"/organizations/#{@org.slug}/settings"}
            class="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-sm font-medium text-zinc-300 transition hover:bg-white/[0.08] hover:text-white"
          >
            <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
          </.link>
          <%= unless @local_mode do %>
            <%= if @can_manage do %>
              <button
                type="button"
                phx-click="open_invite"
                class="inline-flex items-center gap-2 rounded-full bg-lime-300 px-4 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
              >
                <.icon name="hero-plus" class="size-4" /> Invite member
              </button>
            <% end %>
          <% end %>
        </div>
      </div>

      <%= if @invite_token do %>
        <div class="mb-6 rounded-2xl border border-lime-300/30 bg-lime-300/5 p-5">
          <p class="text-sm font-medium text-lime-200">
            Invitation token issued. Send this link to the invitee — the token will not be shown again.
          </p>
          <pre class="mt-2 rounded-lg bg-black/30 px-4 py-2 font-mono text-xs text-zinc-300"><code id="invite-token-value">/cloud/invitations/{@invite_token}</code></pre>
          <button
            type="button"
            phx-click="dismiss-token"
            class="mt-3 text-xs font-medium text-zinc-400 transition hover:text-white"
          >
            Dismiss
          </button>
        </div>
      <% end %>

      <section class="mb-6 rounded-3xl border border-white/10 bg-zinc-900/70 p-6 shadow-2xl shadow-black/20 backdrop-blur">
        <dl class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <div>
            <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-zinc-500">Name</dt>
            <dd class="mt-1 text-sm text-white">{@org.name}</dd>
          </div>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-zinc-500">Slug</dt>
            <dd class="mt-1 font-mono text-sm text-zinc-300">{@org.slug}</dd>
          </div>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-zinc-500">Status</dt>
            <dd class="mt-1 text-sm capitalize text-white">{@org.status}</dd>
          </div>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-zinc-500">Members</dt>
            <dd class="mt-1 text-sm text-white">{@member_count}</dd>
          </div>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-zinc-500">
              Monthly budget
            </dt>
            <dd class="mt-1 text-sm text-white">
              <%= if @budget_cents > 0 do %>
                {"$#{Float.round(@budget_cents / 100, 2)}"}
              <% else %>
                <span class="text-zinc-500">—</span>
              <% end %>
            </dd>
          </div>
          <div>
            <dt class="text-xs font-semibold uppercase tracking-[0.14em] text-zinc-500">Created</dt>
            <dd class="mt-1 text-sm text-white">
              {Calendar.strftime(@org.inserted_at, "%b %d, %Y")}
            </dd>
          </div>
        </dl>
      </section>

      <%= if @local_mode do %>
        <section class="rounded-3xl border border-white/10 bg-zinc-900/70 p-12 text-center shadow-2xl shadow-black/20 backdrop-blur">
          <.icon name="hero-users" class="mx-auto size-10 text-zinc-600" />
          <p class="mt-4 text-base font-medium text-white">
            Member management is not available in local mode.
          </p>
          <p class="mt-1 text-sm text-zinc-500">
            Switch to cloud or self-hosted mode to invite teammates and manage roles.
          </p>
        </section>
      <% else %>
        <section class="rounded-3xl border border-white/10 bg-zinc-900/70 shadow-2xl shadow-black/20 backdrop-blur">
          <div class="overflow-x-auto">
            <table class="min-w-full divide-y divide-white/10 text-left text-sm">
              <thead class="bg-white/[0.03] text-xs uppercase tracking-[0.14em] text-zinc-500">
                <tr>
                  <th class="px-5 py-3 font-semibold">Email</th>
                  <th class="px-5 py-3 font-semibold">Role</th>
                  <th class="px-5 py-3 font-semibold">Status</th>
                  <th class="px-5 py-3 font-semibold"></th>
                </tr>
              </thead>
              <tbody class="divide-y divide-white/10">
                <%= if @memberships == [] do %>
                  <tr>
                    <td colspan="4" class="px-5 py-12 text-center">
                      <p class="text-base font-medium text-white">No members yet.</p>
                      <p class="mt-1 text-sm text-zinc-500">
                        Invite teammates to collaborate on this organization.
                      </p>
                    </td>
                  </tr>
                <% else %>
                  <%= for m <- @memberships do %>
                    <tr id={"membership-#{m.id}"} class="transition hover:bg-white/[0.03]">
                      <td class="px-5 py-4 font-medium text-white">
                        {(m.user && m.user.email) || "—"}
                      </td>
                      <td class="px-5 py-4">
                        <%= if @can_manage do %>
                          <form phx-change="change-role">
                            <input type="hidden" name="membership-id" value={m.id} />
                            <select
                              name="role"
                              class="rounded-lg border border-white/10 bg-zinc-900 px-2.5 py-1.5 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
                            >
                              <option value="owner" selected={m.role == "owner"}>owner</option>
                              <option value="admin" selected={m.role == "admin"}>admin</option>
                              <option value="member" selected={m.role == "member"}>member</option>
                              <option value="viewer" selected={m.role == "viewer"}>viewer</option>
                            </select>
                          </form>
                        <% else %>
                          <span class="text-sm text-zinc-400">{m.role}</span>
                        <% end %>
                      </td>
                      <td class="px-5 py-4">
                        <span class={[
                          "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                          m.status == "active" &&
                            "bg-emerald-300/10 text-emerald-200 ring-emerald-200/20",
                          m.status == "pending" && "bg-amber-300/10 text-amber-200 ring-amber-200/20",
                          m.status == "revoked" && "bg-zinc-400/10 text-zinc-400 ring-zinc-500/20"
                        ]}>
                          {m.status}
                        </span>
                      </td>
                      <td class="px-5 py-4 text-right">
                        <%= if @can_manage and m.status != "revoked" do %>
                          <button
                            type="button"
                            phx-click="revoke"
                            phx-value-membership-id={m.id}
                            data-confirm={"Revoke membership for #{m.user && m.user.email}?"}
                            class="text-sm font-medium text-red-400 transition hover:text-red-300"
                          >
                            Revoke
                          </button>
                        <% end %>
                      </td>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>
        </section>
      <% end %>

      <.invite_modal
        :if={@show_invite_modal}
        form={@invite_form}
        error={@invite_error}
      />
    </section>
    """
  end

  attr :form, :map, required: true
  attr :error, :string, default: nil

  defp invite_modal(assigns) do
    ~H"""
    <div
      id="invite-member-modal"
      class="relative z-50"
      phx-mounted={Phoenix.LiveView.JS.show(to: "#invite-member-modal")}
      phx-remove={Phoenix.LiveView.JS.hide(to: "#invite-member-modal")}
    >
      <div
        class="fixed inset-0 bg-black/70 backdrop-blur-sm transition-opacity"
        phx-click="close_invite"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border border-white/10 bg-zinc-900/95 p-6 shadow-2xl shadow-black/50">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-white">Invite member</h2>
            <button
              type="button"
              phx-click="close_invite"
              class="rounded-md text-zinc-400 transition hover:text-white"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <.form for={@form} phx-submit="invite" id="invite-form" class="space-y-4">
            <.input
              field={@form[:email]}
              type="email"
              label="Email"
              placeholder="teammate@example.com"
              required
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
            />

            <.input
              field={@form[:role]}
              type="select"
              label="Role"
              options={[
                {"viewer", "viewer"},
                {"member", "member"},
                {"admin", "admin"},
                {"owner", "owner"}
              ]}
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
            />

            <%= if @error do %>
              <p class="rounded-lg bg-red-500/10 px-3 py-2 text-sm text-red-300">{@error}</p>
            <% end %>

            <div class="flex items-center justify-end gap-3 pt-4">
              <button
                type="button"
                phx-click="close_invite"
                class="rounded-full px-4 py-2 text-sm font-medium text-zinc-400 transition hover:text-white"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center gap-2 rounded-full bg-lime-300 px-5 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
              >
                Send invitation
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp load_memberships(org_id) do
    Accounts.list_memberships_for_org(org_id)
    |> Enum.reject(&(&1.status == "revoked"))
    |> Repo.preload(:user)
  end

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end

  defp validate_email(""), do: {:error, "Email is required"}

  defp validate_email(email) do
    if Regex.match?(~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, email),
      do: :ok,
      else: {:error, "Invalid email format"}
  end

  defp find_or_create_user(email) do
    case Accounts.get_user_by_email(email) do
      nil -> Accounts.create_user(%{email: email})
      user -> {:ok, user}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(:already_member), do: "This user is already a member or has a pending invite."
  defp format_error(%Ecto.Changeset{}), do: "Could not invite member."
  defp format_error(reason), do: inspect(reason)
end
