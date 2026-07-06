defmodule ControlKeelWeb.InvitationLive do
  @moduledoc """
  Invitation-acceptance page at `/cloud/invitations/:token`.

  Renders the org name and role for the invitee, then requires them to confirm
  the email the invitation was issued to. Email-only confirmation is honest
  about the current auth model — invitation tokens are the source of trust;
  the email confirmation is a sanity check that the right person opened the
  link.

  When the invitation has already been accepted or the token is invalid the
  page renders a clean error state instead of leaking which case it is.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket = assign(socket, :page_title, "Cloud invitation")

    case Accounts.lookup_invitation(token) do
      {:ok, %{membership: membership, org: org, user: user}} ->
        {:ok,
         socket
         |> assign(:state, :ready)
         |> assign(:token, token)
         |> assign(:org, org)
         |> assign(:membership, membership)
         |> assign(:invited_user, user)
         |> assign(:form_error, nil)
         |> assign(:email_input, "")}

      {:error, :already_accepted} ->
        {:ok, assign(socket, :state, :already_accepted)}

      {:error, :invalid_token} ->
        {:ok, assign(socket, :state, :invalid)}
    end
  end

  @impl true
  def handle_event("accept", %{"email" => email}, socket) do
    case socket.assigns.state do
      :ready ->
        normalized = email |> to_string() |> String.downcase() |> String.trim()
        expected = socket.assigns.invited_user.email
        user_id = socket.assigns.invited_user.id

        cond do
          normalized != expected ->
            {:noreply,
             socket
             |> assign(:form_error, "Email does not match the invitation.")
             |> assign(:email_input, email)}

          true ->
            case Accounts.accept_invitation(socket.assigns.token, user_id) do
              {:ok, membership} ->
                # Auto-login: invite token was the proof of identity. Mint a
                # signed completion token and hand off to AuthController to
                # set session keys (LiveView can't put_session/3 directly).
                completion_token =
                  ControlKeelWeb.AuthController.sign_completion_token(
                    membership.user_id,
                    membership.org_id
                  )

                {:noreply, redirect(socket, to: ~p"/auth/complete/#{completion_token}")}

              {:error, :invalid_token} ->
                {:noreply, assign(socket, :state, :invalid)}

              {:error, :already_accepted} ->
                {:noreply, assign(socket, :state, :already_accepted)}

              {:error, _reason} ->
                {:noreply,
                 socket
                 |> assign(:form_error, "Could not accept invitation. Try again later.")
                 |> assign(:email_input, email)}
            end
        end

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(%{state: :ready} = assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section id="invitation-page" class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Cloud</p>
            <h1 class="ck-section-title">Join {@org.name}</h1>
            <p class="ck-lead ck-lead-tight">
              You've been invited as <strong>{@membership.role}</strong>.
            </p>
          </div>
        </div>

        <div class="ck-card">
          <p>
            Confirm the email this invitation was issued to: <strong><code>{@invited_user.email}</code></strong>.
          </p>

          <form id="invitation-accept-form" phx-submit="accept">
            <label class="ck-field">
              <span class="ck-field-label">Email</span>
              <input
                type="email"
                name="email"
                value={@email_input}
                required
                autocomplete="email"
              />
            </label>

            <%= if @form_error do %>
              <p class="ck-note ck-note-danger" id="invitation-form-error">{@form_error}</p>
            <% end %>

            <button type="submit" class="ck-btn ck-btn-primary">Accept invitation</button>
          </form>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  def render(%{state: :accepted} = assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section id="invitation-page" class="ck-shell ck-shell-tight">
        <div class="ck-card">
          <h1 class="ck-section-title">You're in.</h1>
          <p>Your membership is now active.</p>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  def render(%{state: :already_accepted} = assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section id="invitation-page" class="ck-shell ck-shell-tight">
        <div class="ck-card">
          <h1 class="ck-section-title">Already accepted</h1>
          <p>
            This invitation has already been used. If you didn't accept it, contact the org owner.
          </p>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  def render(%{state: :invalid} = assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section id="invitation-page" class="ck-shell ck-shell-tight">
        <div class="ck-card">
          <h1 class="ck-section-title">Invitation not found</h1>
          <p>
            This invitation link is no longer valid. Ask the org owner to issue a new invitation.
          </p>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end
end
