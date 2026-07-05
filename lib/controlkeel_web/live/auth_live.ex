defmodule ControlKeelWeb.AuthLive do
  @moduledoc """
  Sign-in page for cloud/self_hosted mode.

  Presents an org-slug form that redirects to the OIDC start endpoint.
  In local mode this page is accessible but unnecessary — users have no
  org and no SSO.

  Flow:
    1. User visits /auth/login
    2. Enters org slug (e.g. "acme")
    3. Submits → redirect to /auth/oidc/start?org=acme
    4. OIDC round-trip → /auth/oidc/callback → sets session → /cloud/projects

  Invitation holders use their invite link (/cloud/invitations/:token) instead.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign in")
     |> assign(:slug, "")
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("submit", %{"slug" => raw_slug}, socket) do
    slug = raw_slug |> to_string() |> String.trim() |> String.downcase()

    cond do
      slug == "" ->
        {:noreply, assign(socket, :error, "Enter your organization slug.")}

      Accounts.get_org_by_slug(slug) == nil ->
        {:noreply,
         assign(socket, :error, "Organization not found. Check the slug and try again.")}

      true ->
        {:noreply, redirect(socket, external: "/auth/oidc/start?org=#{slug}")}
    end
  end

  @impl true
  def handle_event("change", %{"slug" => slug}, socket) do
    {:noreply, socket |> assign(:slug, slug) |> assign(:error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section class="ck-shell" style="max-width: 480px; margin: 6rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">ControlKeel Cloud</p>
            <h1 class="ck-section-title">Sign in</h1>
            <p class="ck-lead ck-lead-tight">Enter your organization slug to continue with SSO.</p>
          </div>
        </div>

        <.form for={%{}} phx-submit="submit" phx-change="change" class="mt-6 flex flex-col gap-4">
          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Organization slug</label>
            <input
              type="text"
              name="slug"
              value={@slug}
              placeholder="acme"
              autocomplete="organization"
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2.5 text-white placeholder-zinc-500 focus:outline-none focus:ring-2 focus:ring-lime-300"
            />
            <%= if @error do %>
              <p class="mt-1 text-sm text-red-400">{@error}</p>
            <% end %>
          </div>

          <button
            type="submit"
            class="rounded-lg bg-lime-300 px-5 py-2.5 text-sm font-semibold text-zinc-950 hover:bg-lime-200 transition"
          >
            Continue with SSO
          </button>
        </.form>

        <p class="mt-8 text-sm text-zinc-500">
          Joining via an invitation?
          <span class="text-zinc-400">Use the invite link from your email instead.</span>
        </p>
      </section>
    </DashboardLayout.dashboard>
    """
  end
end
