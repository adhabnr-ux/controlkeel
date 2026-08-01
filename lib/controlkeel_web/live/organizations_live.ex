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
      |> assign(
        :page_action,
        %{label: "New Organization", event: "new_org", icon: "hero-plus"}
      )
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
    <section class="w-full">
      <div class="bg-card border rounded-2xl shadow-card overflow-clip">
        <table class="min-w-full divide-y divide-border text-left text-sm">
          <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
            <tr>
              <th class="px-5 py-3 font-semibold">Name</th>
              <th class="px-5 py-3 font-semibold">Slug</th>
              <th class="px-5 py-3 font-semibold">Status</th>
              <th class="px-5 py-3 font-semibold">Role</th>
              <th class="px-5 py-3 font-semibold w-px whitespace-nowrap"></th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= if @orgs == [] do %>
              <tr>
                <td colspan="5" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No organizations yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Create an organization to group workspaces, members, and budgets.
                  </p>
                </td>
              </tr>
            <% else %>
              <%= for row <- @orgs do %>
                <tr class="transition hover:bg-muted/30">
                  <td class="max-w-sm px-5 py-4">
                    <p class="font-medium text-foreground">{row.org.name}</p>
                  </td>
                  <td class="px-5 py-4 font-mono text-xs text-muted-foreground">{row.org.slug}</td>
                  <td class="px-5 py-4">
                    <span class={[
                      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                      row.org.status == "active" &&
                        "bg-success/10 text-success ring-success/20",
                      row.org.status != "active" &&
                        "bg-muted text-muted-foreground ring-border"
                    ]}>
                      {row.org.status}
                    </span>
                  </td>
                  <td class="px-5 py-4">
                    <.role_badge role={row.role} />
                  </td>
                  <td class="px-4 text-right whitespace-nowrap w-px">
                    <a
                      href={~p"/organizations/#{row.org.slug}"}
                      class="inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-xs font-semibold text-muted-foreground transition hover:border-primary/40 hover:bg-primary/10 hover:text-foreground"
                    >
                      View <.icon name="hero-arrow-right" class="size-3" />
                    </a>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>

        <.create_modal :if={@show_create_modal} form={@form} />
      </div>
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
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click="cancel_new"
        aria-label="Close modal"
      />

      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class="w-full max-w-md rounded-2xl border bg-card/95 p-6 shadow-card">
          <div class="mb-5 flex items-center justify-between">
            <h2 class="text-lg font-semibold text-foreground">New organization</h2>
            <button
              type="button"
              phx-click="cancel_new"
              class="rounded-md text-muted-foreground transition hover:text-foreground"
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
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />

            <.input
              field={@form[:slug]}
              type="text"
              label="Slug"
              placeholder="acme-inc"
              class="w-full rounded-xl border border-input bg-background px-3 py-2 text-sm text-foreground focus:border-primary focus:outline-none focus:ring-1 focus:ring-primary"
            />

            <p class="text-xs text-muted-foreground">
              Lowercase letters, numbers, and hyphens. Used in URLs.
            </p>

            <div class="flex items-center justify-end gap-3 border-t pt-4">
              <button
                type="button"
                phx-click="cancel_new"
                class="rounded-full px-4 py-2 text-sm font-medium text-muted-foreground transition hover:text-foreground"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-foreground shadow-lg shadow-primary/20 transition hover:-translate-y-0.5 hover:bg-primary"
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
        @role == "owner" && "bg-primary/10 text-primary ring-primary/20",
        @role == "admin" && "bg-info/10 text-info ring-info/20",
        @role in ["member", "viewer"] && "bg-muted text-muted-foreground ring-border"
      ]}>
        {@role}
      </span>
    <% else %>
      <span class="text-xs text-muted-foreground">—</span>
    <% end %>
    """
  end
end
