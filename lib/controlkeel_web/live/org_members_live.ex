defmodule ControlKeelWeb.OrgMembersLive do
  @moduledoc """
  Member management for an org at `/org/:slug/members`.

  Admin+owner only. Allows:
    - List active and pending memberships (preloaded with the user)
    - Invite a new member by email + role (creates pending Membership;
      raw invitation token is displayed once for copy-paste, since the
      real mailer is deferred to P1c)
    - Revoke a membership (last-owner protected)
    - Change a role (last-owner protected)

  Cross-org access is rejected at mount.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Repo

  @valid_roles ~w(owner admin member viewer)

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
            {:ok,
             socket
             |> assign(:page_title, "Members — #{org.name}")
             |> assign(:org, org)
             |> assign(:memberships, load_memberships(org.id))
             |> assign(:invite_form, to_form(%{"email" => "", "role" => "member"}, as: :invite))
             |> assign(:invite_token, nil)
             |> assign(:invite_error, nil)
             |> assign(:current_user, socket.assigns[:current_user])}
        end
    end
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
       |> assign(:invite_token, raw_token)
       |> assign(:invite_error, nil)
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
    <DashboardLayout.dashboard flash={@flash}>
      <section class="ck-shell" style="max-width: 920px; margin: 4rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">{@org.name}</p>
            <h1 class="ck-section-title">Members</h1>
            <p class="ck-lead ck-lead-tight">
              Invite teammates and manage roles. Owners can promote and demote; the last owner is protected.
            </p>
          </div>
          <div>
            <.link navigate={~p"/org/#{@org.slug}/settings/auth"} class="ck-btn ck-btn-secondary">
              Auth settings
            </.link>
          </div>
        </div>

        <%= if @invite_token do %>
          <div
            class="ck-card mt-6"
            id="invite-token-banner"
            style="border-color: rgba(190, 242, 100, 0.4);"
          >
            <p>
              <strong>Invitation token issued.</strong>
              Send this link to the invitee — the token will not be shown again.
            </p>
            <pre><code id="invite-token-value">/cloud/invitations/{@invite_token}</code></pre>
            <button type="button" phx-click="dismiss-token" class="ck-btn ck-btn-secondary">
              Dismiss
            </button>
          </div>
        <% end %>

        <div class="ck-card mt-6">
          <h2 class="ck-section-subtitle">Invite member</h2>
          <.form for={@invite_form} phx-submit="invite" class="flex flex-col gap-3">
            <div class="grid grid-cols-3 gap-3">
              <div class="col-span-2">
                <label class="block text-sm font-medium text-zinc-300 mb-1">Email</label>
                <input
                  type="email"
                  name="invite[email]"
                  value={@invite_form[:email].value || ""}
                  required
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">Role</label>
                <select
                  name="invite[role]"
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                >
                  <option value="viewer">viewer</option>
                  <option value="member" selected>member</option>
                  <option value="admin">admin</option>
                  <option value="owner">owner</option>
                </select>
              </div>
            </div>
            <%= if @invite_error do %>
              <p class="ck-note ck-note-danger">{@invite_error}</p>
            <% end %>
            <button type="submit" class="ck-btn ck-btn-primary self-start">Send invitation</button>
          </.form>
        </div>

        <div class="ck-card mt-6">
          <h2 class="ck-section-subtitle">Current members</h2>
          <table class="ck-table">
            <thead>
              <tr>
                <th>Email</th>
                <th>Role</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <%= for m <- @memberships do %>
                <tr id={"membership-#{m.id}"}>
                  <td>{(m.user && m.user.email) || "—"}</td>
                  <td>
                    <form phx-change="change-role">
                      <input type="hidden" name="membership-id" value={m.id} />
                      <select
                        name="role"
                        class="rounded-md border border-white/10 bg-zinc-900 px-2 py-1 text-sm text-white"
                      >
                        <option value="owner" selected={m.role == "owner"}>owner</option>
                        <option value="admin" selected={m.role == "admin"}>admin</option>
                        <option value="member" selected={m.role == "member"}>member</option>
                        <option value="viewer" selected={m.role == "viewer"}>viewer</option>
                      </select>
                    </form>
                  </td>
                  <td>{m.status}</td>
                  <td>
                    <%= if m.status != "revoked" do %>
                      <button
                        type="button"
                        phx-click="revoke"
                        phx-value-membership-id={m.id}
                        data-confirm={"Revoke membership for #{m.user && m.user.email}?"}
                        class="ck-btn ck-btn-danger"
                      >
                        Revoke
                      </button>
                    <% end %>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp load_memberships(org_id) do
    Accounts.list_memberships_for_org(org_id) |> Repo.preload(:user)
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
  defp format_error(%Ecto.Changeset{}), do: "Could not invite member."
  defp format_error(reason), do: inspect(reason)
end
