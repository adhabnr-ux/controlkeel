defmodule ControlKeelWeb.AuthLive do
  @moduledoc """
  Sign-in entry point at `/auth/login`.

  Authentication is provider-only: Google and GitHub OAuth buttons. No
  email/password fallback. The actual OAuth dance lives in
  `ControlKeelWeb.OAuthLoginController` and `ControlKeel.Accounts.OAuthProviders`.

  Buttons are only rendered for providers whose client ID + secret are
  configured at boot via `config :controlkeel, :oauth_providers`.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts.OAuthProviders

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign in")
     |> assign(:providers, OAuthProviders.configured())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="ck-shell" style="max-width: 480px; margin: 4rem auto;">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <div class="mb-8">
        <.link
          href={~p"/"}
          class="inline-flex items-center gap-1 text-sm text-zinc-500 hover:text-lime-300 transition"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Home
        </.link>
      </div>

      <div class="ck-section-header">
        <div>
          <p class="ck-kicker">ControlKeel</p>
          <h1 class="ck-section-title">Sign in</h1>
          <p class="ck-lead ck-lead-tight">
            Choose an identity provider. We'll create your account on first visit and recognize you next time.
          </p>
        </div>
      </div>

      <div class="mt-6 flex flex-col gap-3">
        <a
          :if={:google in @providers}
          href={~p"/auth/google/request"}
          class="inline-flex items-center justify-center gap-3 rounded-lg border border-white/15 bg-zinc-900 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-zinc-800"
        >
          <.icon name="hero-globe-alt" class="size-5" /> Continue with Google
        </a>

        <a
          :if={:github in @providers}
          href={~p"/auth/github/request"}
          class="inline-flex items-center justify-center gap-3 rounded-lg border border-white/15 bg-zinc-900 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-zinc-800"
        >
          <.icon name="hero-code-bracket" class="size-5" /> Continue with GitHub
        </a>

        <%= if @providers == [] do %>
          <div class="rounded-lg border border-yellow-400/30 bg-yellow-500/10 px-4 py-3 text-sm text-yellow-100">
            No identity providers are configured. Set <code class="rounded bg-black/30 px-1 py-0.5">GOOGLE_OAUTH_CLIENT_ID</code>/
            <code class="rounded bg-black/30 px-1 py-0.5">GOOGLE_OAUTH_CLIENT_SECRET</code>
            or <code class="rounded bg-black/30 px-1 py-0.5">GITHUB_OAUTH_CLIENT_ID</code>/
            <code class="rounded bg-black/30 px-1 py-0.5">GITHUB_OAUTH_CLIENT_SECRET</code>
            to enable sign-in.
          </div>
        <% end %>
      </div>

    </section>
    """
  end
end
