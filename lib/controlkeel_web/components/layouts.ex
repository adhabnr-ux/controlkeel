defmodule ControlKeelWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ControlKeelWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen bg-zinc-950 text-zinc-100">
      <aside class="fixed inset-y-0 left-0 z-40 hidden w-64 flex-col border-r border-white/10 bg-zinc-950/95 px-4 py-5 shadow-2xl shadow-black/30 lg:flex">
        <a href={~p"/"} class="flex items-center gap-3 rounded-2xl px-2 py-1.5">
          <span class="flex size-10 items-center justify-center rounded-xl bg-lime-300 text-zinc-950 shadow-lg shadow-lime-300/20">
            <.icon name="hero-bolt-solid" class="size-5" />
          </span>
          <span>
            <span class="block text-sm font-semibold tracking-wide text-white">ControlKeel</span>
            <span class="block text-xs text-zinc-500">Governed delivery</span>
          </span>
        </a>

        <nav data-sidebar class="mt-8 flex flex-1 flex-col gap-1 text-sm">
          <a
            href={~p"/"}
            data-sidebar-link
            class="group flex items-center gap-3 rounded-xl bg-white/10 px-3 py-2.5 font-medium text-white shadow-sm ring-1 ring-white/10 transition hover:bg-white/15"
          >
            <.icon name="hero-squares-2x2" class="size-4 text-lime-300" /> Dashboard
          </a>
          <a
            href={~p"/start"}
            data-sidebar-link
            class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
          >
            <.icon name="hero-rocket-launch" class="size-4 text-zinc-500 group-hover:text-lime-300" />
            Missions
          </a>
          <a
            href={~p"/proofs"}
            data-sidebar-link
            class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
          >
            <.icon name="hero-shield-check" class="size-4 text-zinc-500 group-hover:text-lime-300" />
            Proofs
          </a>
          <a
            href={~p"/benchmarks"}
            data-sidebar-link
            class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
          >
            <.icon
              name="hero-chart-bar-square"
              class="size-4 text-zinc-500 group-hover:text-lime-300"
            /> Benchmarks
          </a>
          <a
            href={~p"/ship"}
            data-sidebar-link
            class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
          >
            <.icon name="hero-paper-airplane" class="size-4 text-zinc-500 group-hover:text-lime-300" />
            Ship Metrics
          </a>
          <a
            href={~p"/findings"}
            data-sidebar-link
            class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
          >
            <.icon
              name="hero-exclamation-triangle"
              class="size-4 text-zinc-500 group-hover:text-lime-300"
            /> Findings
          </a>
          <a
            href={~p"/observability"}
            data-sidebar-link
            class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
          >
            <.icon name="hero-signal" class="size-4 text-zinc-500 group-hover:text-lime-300" />
            Observability
          </a>
        </nav>

        <div class="rounded-2xl border border-lime-300/20 bg-lime-300/10 p-4">
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-200">Runtime</p>
          <p class="mt-2 text-sm font-medium text-white">Policy gated</p>
          <p class="mt-1 text-xs leading-5 text-zinc-400">
            Findings, budget, and proof stay visible while agents execute.
          </p>
        </div>
      </aside>

      <div class="lg:pl-64">
        <header class="sticky top-0 z-30 border-b border-white/10 bg-zinc-950/85 backdrop-blur-xl">
          <div class="flex h-16 items-center justify-between gap-4 px-4 sm:px-6 lg:px-8">
            <div class="flex min-w-0 items-center gap-3">
              <a href={~p"/"} class="flex items-center gap-2 lg:hidden">
                <span class="flex size-9 items-center justify-center rounded-xl bg-lime-300 text-zinc-950">
                  <.icon name="hero-bolt-solid" class="size-5" />
                </span>
                <span class="text-sm font-semibold text-white">ControlKeel</span>
              </a>
              <div class="hidden min-w-0 lg:block">
                <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
                  Mission Control
                </p>
                <p class="truncate text-sm text-zinc-400">
                  Live governance, proof, and delivery telemetry
                </p>
              </div>
            </div>

            <div class="flex items-center gap-3">
              <a
                href={~p"/skills"}
                class="hidden items-center gap-2 rounded-full border border-white/10 px-3 py-2 text-sm font-medium text-zinc-300 transition hover:border-lime-300/40 hover:bg-lime-300/10 hover:text-white sm:inline-flex"
              >
                <.icon name="hero-puzzle-piece" class="size-4" /> Skills
              </a>
              <.theme_toggle />
              <details class="group relative">
                <summary class="flex cursor-pointer list-none items-center gap-2 rounded-full border border-white/10 bg-white/5 p-1 pr-3 transition hover:bg-white/10">
                  <span class="flex size-8 items-center justify-center rounded-full bg-zinc-800 text-xs font-semibold text-lime-200 ring-1 ring-white/10">
                    CK
                  </span>
                  <span class="hidden text-sm font-medium text-zinc-200 sm:inline">Operator</span>
                  <.icon
                    name="hero-chevron-down-micro"
                    class="size-4 text-zinc-500 transition group-open:rotate-180"
                  />
                </summary>
                <div class="absolute right-0 mt-2 w-56 rounded-2xl border border-white/10 bg-zinc-900 p-2 shadow-2xl shadow-black/40">
                  <a
                    href={~p"/policies"}
                    class="flex items-center gap-2 rounded-xl px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 hover:text-white"
                  >
                    <.icon name="hero-adjustments-horizontal" class="size-4" /> Policy Studio
                  </a>
                  <a
                    href={~p"/deploy"}
                    class="flex items-center gap-2 rounded-xl px-3 py-2 text-sm text-zinc-300 hover:bg-white/10 hover:text-white"
                  >
                    <.icon name="hero-cloud-arrow-up" class="size-4" /> Deploy
                  </a>
                </div>
              </details>
            </div>
          </div>
        </header>

        <main class="min-h-[calc(100vh-4rem)] bg-[radial-gradient(circle_at_top_left,rgba(190,242,100,0.12),transparent_28rem),linear-gradient(180deg,#0a0a0a_0%,#111113_48%,#18181b_100%)] px-4 py-6 sm:px-6 lg:px-8">
          {render_slot(@inner_block)}
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex w-28 items-center rounded-full border border-white/10 bg-white/5 p-1">
      <div class="absolute left-1 top-1 h-8 w-8 rounded-full bg-lime-300/90 shadow-sm shadow-lime-300/20 transition-[left] [[data-theme=light]_&]:left-[2.375rem] [[data-theme=dark]_&]:left-[4.5rem]" />

      <button
        class="relative z-10 flex size-8 cursor-pointer items-center justify-center rounded-full text-zinc-400 transition hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        title="Use system theme"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex size-8 cursor-pointer items-center justify-center rounded-full text-zinc-400 transition hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Use light theme"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>

      <button
        class="relative z-10 flex size-8 cursor-pointer items-center justify-center rounded-full text-zinc-400 transition hover:text-white"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Use dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
