defmodule ControlKeelWeb.WorkspaceDetailLive do
  @moduledoc """
  Workspace detail page at `/organizations/:slug/workspaces/:id`.

  Shows the workspace's default information (name, slug, industry, agent,
  compliance profile, monthly budget, status) and the sessions that belong to
  it. Works in local mode (no membership required) and in cloud mode scoped to
  the visitor's organization. The org slug and the workspace id must agree.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.Org
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  @impl true
  def mount(%{"id" => id, "slug" => slug} = _params, _session, socket) do
    with {ws_id, ""} <- Integer.parse(id),
         %Workspace{} = workspace <- Repo.get(Workspace, ws_id),
         :ok <- check_org_slug(workspace, %{slug: slug}),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      sessions = Mission.list_all_sessions(ws_id)

      {:ok,
       socket
       |> assign(:page_title, workspace.name)
       |> assign(:workspace, workspace)
       |> assign(:sessions, sessions)}
    else
      :error ->
        {:ok, redirect_with_flash(socket, :error, "Invalid workspace id.", ~p"/organizations")}

      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/organizations")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/organizations")}
    end
  end

  defp check_org_slug(%Workspace{org_id: org_id}, %{slug: slug}) when is_integer(org_id) do
    case Accounts.get_org_by_slug(slug) do
      %Org{id: ^org_id} -> :ok
      _ -> {:error, "Workspace does not belong to this organization."}
    end
  end

  defp check_org_slug(_, _), do: {:error, "Workspace does not belong to this organization."}

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full space-y-12">
      <div class="flex flex-col justify-between gap-4 lg:flex-row lg:items-end">
        <div class="space-y-2">
          <div class="flex flex-wrap items-center gap-3">
            <h1 class="text-xl font-semibold tracking-tight sm:text-2xl text-foreground">
              {@workspace.name}
            </h1>

            <span class={[
              "inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
              @workspace.status == "active" && "bg-success/10 text-success ring-success/20",
              @workspace.status != "active" && "bg-muted text-muted-foreground ring-border"
            ]}>
              {@workspace.status}
            </span>
          </div>

          <p class="text-sm text-muted-foreground">
            Sessions launched under this workspace are indexed here.
          </p>
        </div>

        <div class="flex flex-wrap gap-x-8 gap-y-3">
          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Slug
            </span>
            <span class="font-mono text-sm text-foreground">{@workspace.slug}</span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Sessions
            </span>
            <span class="text-sm font-semibold text-foreground">{length(@sessions)}</span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Monthly budget
            </span>
            <span class="text-sm font-semibold text-foreground">
              <%= if @workspace.budget_cents > 0 do %>
                {"$#{Float.round(@workspace.budget_cents / 100, 2)}"}
              <% else %>
                <span class="text-muted-foreground">—</span>
              <% end %>
            </span>
          </div>

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium uppercase tracking-[0.14em] text-muted-foreground">
              Created
            </span>
            <span class="text-sm text-foreground">
              {Calendar.strftime(@workspace.inserted_at, "%b %d, %Y")}
            </span>
          </div>
        </div>
      </div>

      <div>
        <div class="flex items-center justify-between gap-3 mb-4">
          <.section_title>Sessions</.section_title>

          <.link
            navigate={~p"/missions/start"}
            class="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition hover:bg-primary/90"
          >
            <.icon name="hero-plus" class="size-4" /> New Session
          </.link>
        </div>

        <div class="bg-card border rounded-2xl shadow-card overflow-clip">
          <table class="min-w-full divide-y divide-border text-left text-sm">
            <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground sticky top-0 z-10">
              <tr>
                <th class="px-5 py-3 font-semibold">Session</th>
                <th class="px-5 py-3 font-semibold">Risk</th>
                <th class="px-5 py-3 font-semibold">Workload</th>
                <th class="px-5 py-3 font-semibold">Findings</th>
                <th class="px-5 py-3 font-semibold">Budget</th>
                <th class="px-5 py-3 font-semibold w-px whitespace-nowrap"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <%= if @sessions == [] do %>
                <tr>
                  <td colspan="6" class="px-5 py-12 text-center">
                    <p class="text-base font-medium text-foreground">No sessions yet.</p>
                    <p class="mt-1 text-sm text-muted-foreground">
                      Sessions launched under this workspace will appear here.
                    </p>
                  </td>
                </tr>
              <% else %>
                <%= for session <- @sessions do %>
                  <tr class="transition hover:bg-muted/30">
                    <td class="max-w-sm px-5 py-4">
                      <p class="font-medium text-foreground">{session.title}</p>
                      <p class="mt-1 line-clamp-1 text-xs text-muted-foreground">
                        {session.objective}
                      </p>
                    </td>
                    <td class="px-5 py-4">
                      <span class={[
                        "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                        session.risk_tier in ["critical", "high"] &&
                          "bg-destructive/10 text-destructive ring-destructive/20",
                        session.risk_tier in ["medium", "moderate"] &&
                          "bg-warning/10 text-warning ring-warning/20",
                        session.risk_tier in ["low"] &&
                          "bg-success/10 text-success ring-success/20",
                        session.risk_tier not in ["critical", "high", "medium", "moderate", "low"] &&
                          "bg-muted text-muted-foreground ring-border"
                      ]}>
                        {session.risk_tier}
                      </span>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon name="hero-list-bullet" class="size-4 text-muted-foreground" />
                        {Enum.count(session.tasks)} tasks
                      </div>
                    </td>
                    <td class="px-5 py-4">
                      <div class="flex items-center gap-2 text-muted-foreground">
                        <.icon name="hero-exclamation-circle" class="size-4 text-muted-foreground" />
                        {Enum.count(session.findings)}
                      </div>
                    </td>
                    <td class="px-5 py-4 text-muted-foreground">
                      ${session.budget_cents |> Kernel./(100) |> trunc()}
                    </td>
                    <td class="px-4 text-right whitespace-nowrap w-px">
                      <.link
                        navigate={~p"/missions/#{session.id}"}
                        class="inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-xs font-semibold text-muted-foreground transition hover:border-primary/40 hover:bg-primary/10 hover:text-foreground"
                      >
                        Inspect <.icon name="hero-arrow-right" class="size-3" />
                      </.link>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </section>
    """
  end

  defp check_workspace_access(%Workspace{org_id: nil}, _assigns), do: :ok

  defp check_workspace_access(%Workspace{org_id: ws_org_id}, assigns) do
    case assigns[:current_org_id] do
      nil ->
        :ok

      org_id when is_integer(org_id) and org_id == ws_org_id ->
        :ok

      _ ->
        {:error, "Workspace belongs to a different organization."}
    end
  end

  defp check_workspace_access(_, _), do: :ok

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> put_flash(kind, msg)
    |> push_navigate(to: path)
  end
end
