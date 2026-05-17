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
      <section class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Install</p>
            <h1 class="ck-section-title">Install ControlKeel</h1>
            <p class="ck-lead ck-lead-tight">
              Choose a bootstrap channel and run the command to install ControlKeel on your workspace or agent runtime.
            </p>
          </div>
          <.link navigate={~p"/skills"} class="ck-link">Back to Skills</.link>
        </div>

        <div class="ck-card">
          <p class="ck-mini-label">Install ControlKeel</p>
          <div class="ck-finding-list">
            <%= for channel <- @install_channels do %>
              <article class="ck-finding-item" id={"install-channel-#{channel.id}"}>
                <div class="ck-finding-head">
                  <h3>{channel.label}</h3>
                  <span class="ck-pill ck-pill-neutral">{Enum.join(channel.platforms, ", ")}</span>
                </div>
                <p class="ck-note">{channel.description}</p>
                <div class="flex items-start gap-2" style="margin-top: 0.5rem;">
                  <code>{channel.command}</code>
                  <button
                    type="button"
                    class="ck-link"
                    id={"copy-install-#{channel.id}"}
                    phx-click="copy_command"
                    phx-value-command={channel.command}
                  >
                    Copy
                  </button>
                </div>
              </article>
            <% end %>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
