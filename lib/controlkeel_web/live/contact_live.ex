defmodule ControlKeelWeb.ContactLive do
  @moduledoc """
  Public contact/support form at `/contact`.

  Submits name, email, and message. Delivers via ControlKeel.Mailer.
  No auth required.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Mailer

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Contact — ControlKeel")
     |> assign(:sent, false)
     |> assign(:form, to_form(%{"name" => "", "email" => "", "message" => ""}, as: :contact))}
  end

  @impl true
  def handle_event("submit", %{"contact" => params}, socket) do
    %{"name" => name, "email" => email, "message" => message} = params

    if valid?(name, email, message) do
      Mailer.deliver(%{
        to: "support@controlkeel.com",
        subject: "Contact form: #{name}",
        body: "From: #{name} <#{email}>\n\n#{message}"
      })

      {:noreply, assign(socket, :sent, true) |> put_flash(:info, "Message sent. We'll get back to you soon.")}
    else
      {:noreply, put_flash(socket, :error, "Please fill in all fields.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 560px; margin: 4rem auto;">
        <h1 class="text-3xl font-bold text-white mb-2">Contact us</h1>
        <p class="text-sm text-zinc-400 mb-8">
          Questions, issues, or feedback? We'll respond within 24 hours.
        </p>

        <%= if @sent do %>
          <div class="rounded-lg border border-emerald-500/30 bg-emerald-500/5 px-6 py-4">
            <p class="text-sm text-emerald-300">Message sent. We'll get back to you soon.</p>
          </div>
        <% else %>
          <.form for={@form} phx-submit="submit" class="flex flex-col gap-4">
            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Name</label>
              <input
                type="text"
                name="contact[name]"
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Email</label>
              <input
                type="email"
                name="contact[email]"
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              />
            </div>

            <div>
              <label class="block text-sm font-medium text-zinc-300 mb-1">Message</label>
              <textarea
                name="contact[message]"
                rows="5"
                required
                class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
              >
              </textarea>
            </div>

            <button type="submit" class="ck-btn ck-btn-primary self-start">Send message</button>
          </.form>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp valid?(name, email, message) do
    is_binary(name) and byte_size(name) > 0 and
      is_binary(email) and byte_size(email) > 0 and
      is_binary(message) and byte_size(message) > 0
  end
end
