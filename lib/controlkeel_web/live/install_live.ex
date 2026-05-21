defmodule ControlKeelWeb.InstallLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Skills

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Install ControlKeel")
     |> assign(:install_channels, Skills.install_channels())}
  end

  @impl true
  def handle_event("copy_command", %{"command" => command}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: command})
     |> put_flash(:info, "Copied command to clipboard.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
        <div class="flex flex-col gap-6 rounded-3xl border border-white/10 bg-zinc-950/80 p-6 shadow-xl shadow-black/20">
          <div class="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
            <div class="space-y-3">
              <p class="text-sm font-semibold uppercase tracking-[0.22em] text-lime-300">Install</p>
              <h1 class="text-3xl font-semibold tracking-tight text-white sm:text-4xl">
                Install ControlKeel
              </h1>
              <p class="text-sm leading-7 text-zinc-400">
                Choose a bootstrap channel and run the command to install ControlKeel on your workspace or agent runtime.
              </p>
            </div>
          </div>

          <div class="space-y-4">
            <div class="space-y-4">
              <%= for channel <- @install_channels do %>
                <article
                  class="rounded-3xl border border-white/10 bg-zinc-950/70 p-5 transition hover:border-lime-300/40 hover:bg-zinc-950/90"
                  id={"install-channel-#{channel.id}"}
                >
                  <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                    <div class="space-y-3">
                      <div class="flex flex-wrap items-center gap-3">
                        <h3 class="text-lg font-semibold text-white">{channel.label}</h3>
                        <span class="rounded-full bg-white/5 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-zinc-300">
                          {Enum.join(channel.platforms, ", ")}
                        </span>
                      </div>
                      <p class="text-sm leading-6 text-zinc-400">{channel.description}</p>
                    </div>

                    <button
                      type="button"
                      class="inline-flex items-center justify-center rounded-full bg-lime-300 px-4 py-2 text-sm font-semibold text-zinc-950 transition hover:bg-lime-200"
                      id={"copy-install-#{channel.id}"}
                      phx-click="copy_command"
                      phx-value-command={channel.command}
                    >
                      Copy
                    </button>
                  </div>

                  <div class="mt-4 overflow-hidden rounded-2xl border border-white/10 bg-black/10">
                    <pre class="whitespace-pre-wrap px-4 py-3 text-sm leading-6 text-zinc-100"><code>{channel.command}</code></pre>
                  </div>
                </article>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
