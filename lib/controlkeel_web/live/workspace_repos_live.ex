defmodule ControlKeelWeb.WorkspaceReposLive do
  @moduledoc """
  Workspace GitHub repository bindings at `/workspaces/:id/repos`.

  Admin+owner of the workspace's org can bind / unbind / list
  `WorkspaceGithubRepo` records. The page rejects access if the workspace
  belongs to a different org than the visitor's current_org_id.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Mission
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  @impl true
  def mount(%{"id" => ws_id_param}, _session, socket) do
    with {ws_id, ""} <- Integer.parse(ws_id_param),
         %Workspace{} = workspace <- Repo.get(Workspace, ws_id),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      {:ok,
       socket
       |> assign(:page_title, "Repositories — #{workspace.name}")
       |> assign(:workspace, workspace)
       |> assign(:repos, Mission.list_github_repos(workspace.id))
       |> assign(:bind_form, to_form(empty_bind_params(), as: :bind))
       |> assign(:bind_error, nil)}
    else
      :error ->
        {:ok, redirect_with_flash(socket, :error, "Invalid workspace id.", ~p"/cloud/projects")}

      nil ->
        {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/cloud/projects")}

      {:error, reason} ->
        {:ok, redirect_with_flash(socket, :error, reason, ~p"/cloud/projects")}
    end
  end

  @impl true
  def handle_event("bind", %{"bind" => params}, socket) do
    owner = params["owner"] |> to_string() |> String.trim()
    repo = params["repo"] |> to_string() |> String.trim()
    branch = params["default_branch"] |> to_string() |> String.trim()
    inst_id_raw = params["installation_id"] |> to_string() |> String.trim()

    opts = [
      default_branch: nil_if_empty(branch),
      installation_id: parse_int_or_nil(inst_id_raw)
    ]

    cond do
      owner == "" or repo == "" ->
        {:noreply, assign(socket, :bind_error, "Owner and repo are required.")}

      true ->
        case Mission.bind_github_repo(socket.assigns.workspace.id, owner, repo, opts) do
          {:ok, _binding} ->
            {:noreply,
             socket
             |> assign(:repos, Mission.list_github_repos(socket.assigns.workspace.id))
             |> assign(:bind_form, to_form(empty_bind_params(), as: :bind))
             |> assign(:bind_error, nil)
             |> put_flash(:info, "Bound #{owner}/#{repo}.")}

          {:error, %Ecto.Changeset{} = cs} ->
            msg =
              cs.errors
              |> Enum.map_join(", ", fn {f, {m, _}} -> "#{f}: #{m}" end)

            {:noreply, assign(socket, :bind_error, msg)}
        end
    end
  end

  def handle_event("unbind", %{"owner" => owner, "repo" => repo}, socket) do
    case Mission.unbind_github_repo(socket.assigns.workspace.id, owner, repo) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:repos, Mission.list_github_repos(socket.assigns.workspace.id))
         |> put_flash(:info, "Unbound #{owner}/#{repo}.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Binding not found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 920px; margin: 4rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">{@workspace.name}</p>
            <h1 class="ck-section-title">GitHub repositories</h1>
            <p class="ck-lead ck-lead-tight">
              Bind GitHub repos so missions, findings, and proofs can reference them.
              For governance via the GitHub App, set <code>installation_id</code>.
            </p>
          </div>
        </div>

        <div class="ck-card mt-6">
          <h2 class="ck-section-subtitle">Bind a repository</h2>
          <.form for={@bind_form} phx-submit="bind" class="flex flex-col gap-3">
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">Owner</label>
                <input
                  type="text"
                  name="bind[owner]"
                  value={@bind_form[:owner].value || ""}
                  placeholder="acme"
                  required
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">Repo</label>
                <input
                  type="text"
                  name="bind[repo]"
                  value={@bind_form[:repo].value || ""}
                  placeholder="payments"
                  required
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
            </div>
            <div class="grid grid-cols-2 gap-3">
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">
                  Default branch (optional)
                </label>
                <input
                  type="text"
                  name="bind[default_branch]"
                  value={@bind_form[:default_branch].value || ""}
                  placeholder="main"
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
              <div>
                <label class="block text-sm font-medium text-zinc-300 mb-1">
                  Installation ID (optional)
                </label>
                <input
                  type="number"
                  name="bind[installation_id]"
                  value={@bind_form[:installation_id].value || ""}
                  class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white"
                />
              </div>
            </div>
            <%= if @bind_error do %>
              <p class="ck-note ck-note-danger">{@bind_error}</p>
            <% end %>
            <button type="submit" class="ck-btn ck-btn-primary self-start">Bind repository</button>
          </.form>
        </div>

        <div class="ck-card mt-6">
          <h2 class="ck-section-subtitle">Bound repositories</h2>
          <%= if @repos == [] do %>
            <p class="ck-lead-tight">No repositories bound yet.</p>
          <% else %>
            <table class="ck-table">
              <thead>
                <tr>
                  <th>Owner / Repo</th>
                  <th>Default branch</th>
                  <th>Installation ID</th>
                  <th>Bound at</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <%= for r <- @repos do %>
                  <tr id={"binding-#{r.id}"}>
                    <td><code>{r.owner}/{r.repo}</code></td>
                    <td>{r.default_branch || "—"}</td>
                    <td>{r.installation_id || "—"}</td>
                    <td>{format_dt(r.inserted_at)}</td>
                    <td>
                      <button
                        type="button"
                        phx-click="unbind"
                        phx-value-owner={r.owner}
                        phx-value-repo={r.repo}
                        data-confirm={"Unbind #{r.owner}/#{r.repo}?"}
                        class="ck-btn ck-btn-danger"
                      >
                        Unbind
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp check_workspace_access(%Workspace{org_id: nil}, _assigns),
    do: {:error, "Workspace is not bound to an org yet."}

  defp check_workspace_access(%Workspace{org_id: ws_org_id}, %{
         current_org_id: org_id,
         current_membership: membership
       })
       when is_integer(ws_org_id) and ws_org_id == org_id do
    if membership && Accounts.role_at_least?(membership.role, "admin") do
      :ok
    else
      {:error, "Admin or owner role required to manage repositories."}
    end
  end

  defp check_workspace_access(_, _),
    do: {:error, "Workspace belongs to a different organization."}

  defp empty_bind_params do
    %{"owner" => "", "repo" => "", "default_branch" => "", "installation_id" => ""}
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(value), do: value

  defp parse_int_or_nil(""), do: nil

  defp parse_int_or_nil(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp parse_int_or_nil(_), do: nil

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp format_dt(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
