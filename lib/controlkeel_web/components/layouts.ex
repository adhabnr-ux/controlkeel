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

  Renders a sign-out button at the bottom when a user is signed in and
  the app is running in cloud mode (not local).
  """
  attr :current_user, :any, default: nil

  def sidebar(assigns) do
    assigns = assign_new(assigns, :mode, fn -> ControlKeel.Runtime.Mode.current() end)

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
          href={~p"/organizations"}
          data-sidebar-link
          class="group flex items-center gap-3 rounded-xl px-3 py-2.5 font-medium text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-building-office-2" class="size-4 text-zinc-500 group-hover:text-lime-300" />
          Organizations
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

      <.user_menu
        :if={@current_user != nil and @mode != :local}
        id="sidebar-user-menu"
        current_user={@current_user}
        class="mt-3 border-t border-white/10 pt-3"
        popover_class="bottom-20 right-4"
      />
    </aside>
    """
  end

  attr :id, :string, required: true
  attr :current_user, :any, required: true
  attr :compact, :boolean, default: false
  attr :show_dashboard, :boolean, default: false
  attr :class, :string, default: ""
  attr :popover_class, :string, default: "right-0 top-full mt-2"
  attr :rest, :global

  def user_menu(assigns) do
    ~H"""
    <div {@rest} class={"relative #{@class}"} id={@id}>
      <button
        type="button"
        phx-click={JS.toggle(to: "##{@id}-popover")}
        class={[
          "transition hover:bg-white/10",
          if(@compact,
            do:
              "flex items-center gap-2 rounded-full px-1 py-1 text-sm font-semibold text-zinc-300 hover:text-white",
            else: "flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left"
          )
        ]}
      >
        <span class={[
          "flex shrink-0 items-center justify-center rounded-full bg-lime-300/20 font-semibold text-lime-300",
          if(@compact, do: "size-8", else: "size-8 text-sm ring-1 ring-lime-300/30")
        ]}>
          {String.at(@current_user.name || @current_user.email, 0) |> String.upcase()}
        </span>
        <%= unless @compact do %>
          <span class="min-w-0 flex-1">
            <span class="block truncate text-sm font-medium text-white">
              {@current_user.name || @current_user.email}
            </span>
          </span>
          <.icon name="hero-chevron-down" class="size-4 shrink-0 text-zinc-500" />
        <% end %>
      </button>
      <div
        id={"#{@id}-popover"}
        phx-click-away={JS.hide(to: "##{@id}-popover")}
        class={"hidden absolute #{@popover_class} z-50 w-56 rounded-xl border border-white/10 bg-zinc-900 p-3 shadow-2xl shadow-black/50 backdrop-blur-md"}
      >
        <p class="text-sm font-semibold text-white">{@current_user.name || @current_user.email}</p>
        <p class="mt-0.5 text-xs text-zinc-400">{@current_user.email}</p>
        <div class="my-2 border-t border-white/10"></div>
        <%= if @show_dashboard do %>
          <a
            href={~p"/dashboard"}
            phx-click={JS.hide(to: "##{@id}-popover")}
            class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-zinc-400 transition hover:bg-white/10 hover:text-white"
          >
            <.icon name="hero-squares-2x2" class="size-4" /> Dashboard
          </a>
        <% end %>
        <%!-- TODO: wire up to user settings modal/dialog --%>
        <button
          type="button"
          phx-click={JS.hide(to: "##{@id}-popover")}
          class="flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-cog-6-tooth" class="size-4" /> Settings
        </button>
        <hr class="my-2 border-t border-white/10" />
        <a
          href={~p"/auth/logout"}
          class="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-sm text-zinc-400 transition hover:bg-white/10 hover:text-[var(--ck-danger)]"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Sign out
        </a>
      </div>
    </div>
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
  Renders a breadcrumb trail derived from the current path.

  Automatically maps URL segments to human-readable labels.
  The root always shows a home icon linking to `/dashboard`.
  Intermediate segments are clickable links; the final segment is plain text.

  ## Examples

      <.dashboard_header current_path={@current_path} />
  """
  attr :current_path, :string, default: nil

  def dashboard_header(assigns) do
    assigns = assign_new(assigns, :current_path, fn -> nil end)

    ~H"""
    <div class="mb-4 flex w-full items-center justify-between border-b border-white/10 pb-2">
      <nav :if={@current_path && @current_path != "/"} aria-label="Breadcrumb">
        <ol class="flex items-center gap-1.5 text-sm">
          <li>
            <.link
              navigate={~p"/dashboard"}
              class="flex items-center gap-1 text-zinc-500 transition hover:text-zinc-300"
            >
              <.icon name="hero-home" class="size-3.5" />
            </.link>
          </li>
          <%= for {label, path, final} <- breadcrumb_trail(@current_path) do %>
            <li class="flex items-center gap-1.5">
              <.icon name="hero-chevron-right" class="size-3 text-zinc-600" />
              <%= if final do %>
                <span class="font-medium text-zinc-300">{label}</span>
              <% else %>
                <.link
                  navigate={path}
                  class="text-zinc-500 transition hover:text-zinc-300"
                >
                  {label}
                </.link>
              <% end %>
            </li>
          <% end %>
        </ol>
      </nav>
      <div class="flex items-center gap-2">
        <a
          href={~p"/getting-started"}
          target="_blank"
          rel="noopener"
          class="flex items-center gap-1.5 rounded-xl px-2.5 py-1.5 text-sm text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-book-open" class="size-4 text-zinc-500" /> Docs
        </a>
        <a
          href="https://github.com/aryaminus/controlkeel"
          target="_blank"
          rel="noopener"
          class="flex items-center gap-1.5 rounded-xl px-2.5 py-1.5 text-sm text-zinc-400 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-code-bracket" class="size-4 text-zinc-500" /> GitHub
        </a>
      </div>
    </div>
    """
  end

  @label_map %{
    "dashboard" => "Dashboard",
    "missions" => "Missions",
    "findings" => "Findings",
    "benchmarks" => "Benchmarks",
    "proofs" => "Proofs",
    "reviews" => "Reviews",
    "organizations" => "Organizations",
    "workspaces" => "Workspaces",
    "policies" => "Policy Studio",
    "skills" => "Skills",
    "deploy" => "Deploy",
    "cloud" => "Cloud",
    "observability" => "Observability",
    "repos" => "Repos",
    "service-accounts" => "Service Accounts",
    "webhooks" => "Webhooks",
    "tool-policy" => "Tool Policy",
    "start" => "New Mission",
    "runs" => "Runs",
    "telemetry" => "Telemetry",
    "projects" => "Projects"
  }

  defp breadcrumb_trail(current_path) do
    segments = String.split(current_path, "/", trim: true)

    segments
    |> Enum.with_index()
    |> Enum.map(fn {segment, idx} ->
      path = "/" <> Enum.join(Enum.take(segments, idx + 1), "/")
      label = Map.get(@label_map, segment, segment_name(segment))
      is_final = idx == length(segments) - 1
      {label, path, is_final}
    end)
  end

  defp segment_name(segment) do
    segment
    |> String.replace("-", " ")
    |> title_case()
  end

  defp title_case(string) do
    string
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
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
