defmodule ControlKeelWeb.CommandPill do
  use Phoenix.Component

  import ControlKeelWeb.CoreComponents, only: [icon: 1]

  attr :command, :string, required: true

  def command_pill(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2 text-[var(--ck-muted)] text-xs font-mono border border-[var(--ck-stroke)] rounded-lg px-3 py-2 bg-[rgba(255,255,255,0.015)]">
      <span><%= @command %></span>
      <button
        type="button"
        phx-click="copy_command"
        phx-value-command={@command}
        class="cursor-pointer hover:text-[var(--ck-lime)] transition-colors"
      >
        <.icon name="hero-clipboard" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  defmacro __using__(_opts) do
    quote do
      @impl true
      def handle_event("copy_command", %{"command" => command}, socket) do
        {:noreply,
         socket
         |> push_event("copy-to-clipboard", %{text: command})
         |> put_flash(:info, "Copied command to clipboard.")}
      end
    end
  end
end
