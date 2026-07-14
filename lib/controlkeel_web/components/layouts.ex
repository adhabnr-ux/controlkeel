defmodule ControlKeelWeb.Layouts do
  @moduledoc """
  App layout templates, embedded via `embed_templates "layouts/*"`.

  - `:root` — the HTML skeleton (doctype/head/body), set via `put_root_layout`
    in the browser pipeline.
  - `:public` — marketing chrome (header/footer) for public pages, set per
    controller via `plug :put_layout` (see `PageController`).

  Framework layouts share the page's render context, so assigns like
  `@current_user`, `@flash`, and `@inner_content` are available here without
  any forwarding from callers.
  """

  use ControlKeelWeb, :html

  embed_templates "layouts/*"

  @doc """
  The dashboard sidebar: logo, primary nav, and external links.

  Purely static markup (no assigns), so it is called as `<.sidebar />` from the
  dashboard / observability framework layouts.
  """
  def sidebar(assigns) do
    ~H"""
    <aside class="fixed inset-y-0 left-0 z-40 hidden w-64 flex-col border-r border-white/10 bg-zinc-950/95 px-4 py-5 shadow-2xl shadow-black/30 lg:flex">
      <a href={~p"/dashboard"} class="flex items-center gap-3 rounded-2xl px-2 py-1.5">
        <span class="flex size-10 items-center justify-center rounded-xl bg-lime-300 text-zinc-950 shadow-lg shadow-lime-300/20">
          <.icon name="hero-bolt-solid" class="size-5" />
        </span>
        <span>
          <span class="block text-sm font-semibold tracking-wide text-white">ControlKeel</span>
          <span class="block text-xs text-zinc-500">Governance memory</span>
        </span>
      </a>

      <nav data-sidebar class="mt-8 flex flex-1 flex-col gap-1 text-sm">
        <a
          href={~p"/dashboard"}
          data-sidebar-link
          class="group flex items-center gap-3 rounded-xl bg-white/10 px-3 py-2.5 font-medium text-white shadow-sm ring-1 ring-white/10 transition hover:bg-white/15"
        >
          <.icon name="hero-squares-2x2" class="size-4 text-lime-300" /> Dashboard
        </a>
        <a
          href={~p"/missions"}
          data-sidebar-link
          class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-rocket-launch" class="size-4 text-zinc-500 group-hover:text-lime-300" />
          Missions
        </a>
        <a
          href={~p"/skills"}
          data-sidebar-link
          class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-puzzle-piece" class="size-4 text-zinc-500 group-hover:text-lime-300" />
          Skills
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
          href={~p"/policies"}
          data-sidebar-link
          class="group flex items-center gap-2 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon
            name="hero-adjustments-horizontal"
            class="size-4 text-zinc-500 group-hover:text-lime-300"
          /> Policy Studio
        </a>
        <a
          href={~p"/deploy"}
          data-sidebar-link
          class="group flex items-center gap-2 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-cloud-arrow-up" class="size-4 text-zinc-500 group-hover:text-lime-300" />
          Deploy
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

      <div class="mt-auto border-t border-white/10 pt-3">
        <a
          href={~p"/getting-started"}
          target="_blank"
          rel="noopener"
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-book-open" class="size-4 text-zinc-500" /> Docs
        </a>
        <a
          href="https://github.com/aryaminus/controlkeel"
          target="_blank"
          rel="noopener"
          class="flex items-center gap-3 rounded-xl px-3 py-2 text-sm text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-code-bracket" class="size-4 text-zinc-500" /> GitHub
        </a>
      </div>
    </aside>
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

  # Active-link class for the observability subnav. `path == current_path`
  # highlights the current page.
  defp nav_link_class(path, current_path) do
    active = path == current_path

    base = "text-sm font-medium transition-colors px-3 py-1.5 rounded-lg border"

    if active do
      "#{base} text-[var(--ck-lime)] bg-[rgba(190,242,100,0.1)] border-[var(--ck-lime)]"
    else
      "#{base} text-[var(--ck-text)] hover:text-[var(--ck-lime)] bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] border-[var(--ck-stroke)]"
    end
  end

  # Tab styling for the observability session layout (Overview / Timeline /
  # Memory / Export JSON).
  defp tab_class(path, current_path) do
    if path == current_path do
      "#{tab_base_class()} text-[var(--ck-lime)] bg-[rgba(190,242,100,0.1)] border-[var(--ck-lime)]"
    else
      tab_inactive_class()
    end
  end

  defp tab_inactive_class do
    "#{tab_base_class()} text-[var(--ck-text)] hover:text-[var(--ck-lime)] bg-[rgba(255,255,255,0.03)] hover:bg-[rgba(255,255,255,0.06)] border-[var(--ck-stroke)]"
  end

  defp tab_base_class do
    "text-sm font-medium transition-colors px-3 py-1.5 rounded-lg border"
  end
end
