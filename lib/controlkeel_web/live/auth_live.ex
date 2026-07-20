defmodule ControlKeelWeb.AuthLive do
  @moduledoc """
  Sign-in entry point at `/auth/login`.

  Authentication is provider-only: Google and GitHub OAuth buttons. No
  email/password fallback. The actual OAuth dance lives in
  `ControlKeelWeb.OAuthLoginController` and `ControlKeel.Accounts.OAuthProviders`.

  Only providers whose client_id + client_secret are configured (read from
  `OAuthProviders.configured/0`) are rendered. If neither is configured the
  card shows a "no providers configured" message instead of dead buttons.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts.OAuthProviders

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign in")
     |> assign(:configured_providers, OAuthProviders.configured())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-950 text-white">
      <div class="pointer-events-none absolute inset-0 overflow-hidden">
        <div class="absolute left-1/2 top-8 h-80 w-80 -translate-x-1/2 rounded-full bg-lime-400/10 blur-3xl" />
        <div class="absolute right-0 top-1/4 h-72 w-72 rounded-full bg-sky-400/10 blur-2xl" />
      </div>

      <section class="relative z-10 mx-auto flex min-h-screen w-full max-w-md flex-col justify-center px-4 py-16 sm:px-6 lg:px-8">
        <.flash kind={:info} flash={@flash} />
        <.flash kind={:error} flash={@flash} />

        <div class="mb-10 flex items-center justify-between">
          <.link
            href={~p"/"}
            class="inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.32em] text-slate-400 transition duration-200 hover:text-lime-300"
          >
            <.icon name="hero-arrow-left" class="size-4" /> Home
          </.link>
        </div>

        <div class="overflow-hidden rounded-[2rem] border border-white/10 bg-slate-900/95 p-8 shadow-[0_45px_120px_-40px_rgba(0,0,0,0.9)]">
          <div class="mb-8 text-center">
            <div class="mx-auto mb-5 flex h-16 w-16 items-center justify-center rounded-3xl border border-white/10 bg-white/5 shadow-[0_18px_48px_-30px_rgba(255,255,255,0.75)]">
              <.icon name="hero-key" class="size-7 text-lime-300" />
            </div>
            <h1 class="text-3xl font-semibold tracking-tight text-white">Welcome back</h1>
            <p class="mt-3 text-sm text-slate-400">Sign in to continue to ControlKeel</p>
          </div>

          <div class="mb-6 flex items-center gap-3">
            <div class="flex-1 h-px bg-white/10" />
            <span class="text-[11px] uppercase tracking-[0.28em] text-slate-500">
              Choose provider
            </span>
            <div class="flex-1 h-px bg-white/10" />
          </div>

          <div class="grid gap-3">
            <.link
              :if={:google in @configured_providers}
              href={~p"/auth/google/request"}
              id="auth-google-btn"
              class="group flex items-center justify-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-5 py-3.5 text-sm font-semibold text-white transition duration-200 hover:-translate-y-1 hover:bg-white/15 hover:border-white/20"
            >
              <span class="inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10">
                <svg class="size-5" viewBox="0 0 24 24" aria-hidden="true">
                  <path
                    d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z"
                    fill="#4285F4"
                  />
                  <path
                    d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                    fill="#34A853"
                  />
                  <path
                    d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                    fill="#FBBC05"
                  />
                  <path
                    d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                    fill="#EA4335"
                  />
                </svg>
              </span>
              Continue with Google
            </.link>

            <.link
              :if={:github in @configured_providers}
              href={~p"/auth/github/request"}
              id="auth-github-btn"
              class="group flex items-center justify-center gap-3 rounded-2xl border border-white/10 bg-white/5 px-5 py-3.5 text-sm font-semibold text-white transition duration-200 hover:-translate-y-1 hover:bg-white/15 hover:border-white/20"
            >
              <span class="inline-flex h-10 w-10 items-center justify-center rounded-2xl bg-white/10">
                <svg class="size-5" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
                  <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
                </svg>
              </span>
              Continue with GitHub
            </.link>

            <p :if={@configured_providers == []} class="py-6 text-center text-sm text-slate-400">
              No sign-in providers are configured. Contact your administrator.
            </p>
          </div>

          <p class="mt-7 text-center text-xs text-slate-500 leading-6">
            We'll create your account on first sign-in.
          </p>
        </div>
      </section>
    </div>
    """
  end
end
