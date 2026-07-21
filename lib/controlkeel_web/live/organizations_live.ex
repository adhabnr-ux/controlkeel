defmodule ControlKeelWeb.OrganizationsLive do
  @moduledoc """
  `/organizations` — list and create organizations.

  Local mode (no user) shows every org in the DB and creates bare Org rows.
  Cloud/self_hosted mode shows only orgs where the signed-in user has an
  active membership, and creates an org plus an owner membership in one
  transaction. Create happens in an inline modal — no separate route.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Runtime.Mode

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Organizations")
      |> assign(:show_create_modal, false)
      |> assign(:changeset, Org.changeset(%Org{}, %{}))
      |> assign_form(Org.changeset(%Org{}, %{}))

    {:ok, assign(socket, :orgs, list_orgs_for_socket(socket))}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :org))
  end

  defp list_orgs_for_socket(socket) do
    cond do
      Mode.current() == :local ->
        # Local mode has no membership concept — every row gets role: nil.
        Accounts.list_orgs(status: "active")
        |> Enum.map(&%{org: &1, role: nil})

      user = socket.assigns[:current_user] ->
        Accounts.list_orgs_for_user(user.id)

      true ->
        []
    end
  end

  @impl true
  def handle_event("new_org", _params, socket) do
    changeset = Org.changeset(%Org{}, %{})

    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:changeset, changeset)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("cancel_new", _params, socket) do
    changeset = Org.changeset(%Org{}, %{})

    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:changeset, changeset)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"org" => params}, socket) do
    changeset =
      %Org{}
      |> Org.changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset) |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"org" => params}, socket) do
    case create_org_for_current_mode(socket, params) do
      {:ok, _org} ->
        {:noreply,
         socket
         |> put_flash(:info, "Organization created.")
         |> assign(:show_create_modal, false)
         |> assign(:orgs, list_orgs_for_socket(socket))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset) |> assign_form(changeset)}
    end
  end

  defp create_org_for_current_mode(socket, params) do
    cond do
      Mode.current() == :local ->
        Accounts.create_org(params)

      user = socket.assigns[:current_user] ->
        Accounts.create_org_with_owner(user.id, params)

      true ->
        {:error, :signed_out}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-7xl px-4 py-8 md:py-12">
      <div class="mb-6 flex items-center justify-between gap-4">
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
            Organizations
          </p>
          <h1 class="mt-2 text-3xl font-semibold tracking-tight text-white sm:text-4xl">
            Your organizations
          </h1>
        </div>

        <button
          type="button"
          phx-click="new_org"
          class="inline-flex items-center gap-2 rounded-full bg-lime-300 px-4 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
        >
          <.icon name="hero-plus" class="size-4" /> New Organization
        </button>
      </div>

      <section class="rounded-3xl border border-white/10 bg-zinc-900/70 shadow-2xl shadow-black/20 backdrop-blur">
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-white/10 text-left text-sm">
            <thead class="bg-white/[0.03] text-xs uppercase tracking-[0.14em] text-zinc-500">
              <tr>
                <th class="px-5 py-3 font-semibold">Name</th>
                <th class="px-5 py-3 font-semibold">Slug</th>
                <th class="px-5 py-3 font-semibold">Status</th>
                <th class="px-5 py-3 font-semibold">Role</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-white/10">
              <%= if @orgs == [] do %>
                <tr>
                  <td colspan="4" class="px-5 py-12 text-center">
                    <p class="text-base font-medium text-white">No organizations yet.</p>
                    <p class="mt-1 text-sm text-zinc-500">
                      Create an organization to group workspaces, members, and budgets.
                    </p>
                  </td>
                </tr>
              <% else %>
                <%= for row <- @orgs do %>
                  <tr class="transition hover:bg-white/[0.03]">
                    <td class="px-5 py-4">
                      <.link
                        navigate={~p"/organizations/#{row.org.slug}"}
                        class="font-medium text-white transition hover:text-lime-300"
                      >
                        {row.org.name}
                      </.link>
                    </td>
                    <td class="px-5 py-4 font-mono text-xs text-zinc-400">{row.org.slug}</td>
                    <td class="px-5 py-4">
                      <span class="inline-flex rounded-full bg-emerald-300/10 px-2.5 py-1 text-xs font-semibold capitalize text-emerald-200 ring-1 ring-emerald-200/20">
                        {row.org.status}
                      </span>
                    </td>
                    <td class="px-5 py-4">
                      <.role_badge role={row.role} />
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>

      <.create_modal :if={@show_create_modal} form={@form} />
    </section>
    """
  end

  attr :form, :map, required: true

  defp create_modal(assigns) do
    ~H"""
    <div
      id="organization-create-modal"
      class="relative z-50"
      phx-mounted={Phoenix.LiveView.JS.show(to: "#organization-create-modal")}
      phx-remove={Phoenix.LiveView.JS.hide(to: "#organization-create-modal")}
    >
      <div
        class="fixed inset-0 bg-black/70 backdrop-blur-sm transition-opacity"
        phx-click="cancel_new"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border border-white/10 bg-zinc-900/95 p-6 shadow-2xl shadow-black/50">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-white">New organization</h2>
            <button
              type="button"
              phx-click="cancel_new"
              class="rounded-md text-zinc-400 transition hover:text-white"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <.form
            for={@form}
            phx-change="validate"
            phx-submit="save"
            id="organization-form"
            class="space-y-4"
          >
            <.input
              field={@form[:name]}
              type="text"
              label="Name"
              placeholder="Acme Inc"
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
            />

            <.input
              field={@form[:slug]}
              type="text"
              label="Slug"
              placeholder="acme-inc"
              class="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-sm text-white focus:border-lime-300 focus:outline-none focus:ring-1 focus:ring-lime-300"
            />

            <p class="text-xs text-zinc-500">
              Lowercase letters, numbers, and hyphens. Used in URLs.
            </p>

            <div class="flex items-center justify-end gap-3 border-t border-white/10 pt-4">
              <button
                type="button"
                phx-click="cancel_new"
                class="rounded-full px-4 py-2 text-sm font-medium text-zinc-400 transition hover:text-white"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center gap-2 rounded-full bg-lime-300 px-5 py-2 text-sm font-semibold text-zinc-950 shadow-lg shadow-lime-300/20 transition hover:-translate-y-0.5 hover:bg-lime-200"
              >
                Create organization
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  attr :role, :string, default: nil

  defp role_badge(assigns) do
    ~H"""
    <%= if @role do %>
      <span class={[
        "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
        @role == "owner" && "bg-lime-300/10 text-lime-200 ring-lime-300/20",
        @role == "admin" && "bg-sky-400/10 text-sky-200 ring-sky-300/20",
        @role == "member" && "bg-zinc-400/10 text-zinc-200 ring-zinc-300/20",
        @role == "viewer" && "bg-zinc-400/10 text-zinc-400 ring-zinc-500/20"
      ]}>
        {@role}
      </span>
    <% else %>
      <span class="text-xs text-zinc-600">—</span>
    <% end %>
    """
  end
end
