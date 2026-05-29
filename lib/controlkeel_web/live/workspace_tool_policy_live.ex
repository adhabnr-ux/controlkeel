defmodule ControlKeelWeb.WorkspaceToolPolicyLive do
  @moduledoc """
  Per-workspace MCP tool policy at `/workspaces/:id/tool-policy`.

  Admin+owner can choose one of three modes:
    - `inherit` — fall back to global policy (the default)
    - `allowlist` — only tools in the list are allowed
    - `denylist` — listed tools are denied; everything else allowed

  Cross-org access is rejected at mount.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  @impl true
  def mount(%{"id" => ws_id_param}, _session, socket) do
    with {ws_id, ""} <- Integer.parse(ws_id_param),
         %Workspace{} = workspace <- Repo.get(Workspace, ws_id),
         :ok <- check_workspace_access(workspace, socket.assigns) do
      policy = Accounts.get_workspace_tool_policy(workspace.id)
      tools = WorkspaceToolPolicy.decode_tools(policy)

      {:ok,
       socket
       |> assign(:page_title, "Tool policy — #{workspace.name}")
       |> assign(:workspace, workspace)
       |> assign(:policy, policy)
       |> assign(:modes, WorkspaceToolPolicy.modes())
       |> assign(:form, to_form(%{
         "mode" => policy.mode,
         "tools" => Enum.join(tools, "\n")
       }, as: :policy))
       |> assign(:saved, false)
       |> assign(:error, nil)}
    else
      :error -> {:ok, redirect_with_flash(socket, :error, "Invalid workspace id.", ~p"/cloud/projects")}
      nil -> {:ok, redirect_with_flash(socket, :error, "Workspace not found.", ~p"/cloud/projects")}
      {:error, reason} -> {:ok, redirect_with_flash(socket, :error, reason, ~p"/cloud/projects")}
    end
  end

  @impl true
  def handle_event("submit", %{"policy" => %{"mode" => mode, "tools" => raw}}, socket) do
    tools = parse_tools(raw)

    case Accounts.set_workspace_tool_policy(socket.assigns.workspace.id, mode, tools) do
      {:ok, policy} ->
        {:noreply,
         socket
         |> assign(:policy, policy)
         |> assign(:saved, true)
         |> assign(:error, nil)
         |> put_flash(:info, "Tool policy saved (#{policy.mode}).")}

      {:error, %Ecto.Changeset{} = cs} ->
        msg = Enum.map_join(cs.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
        {:noreply, assign(socket, :error, msg) |> assign(:saved, false)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 720px; margin: 4rem auto;">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">{@workspace.name}</p>
            <h1 class="ck-section-title">Tool policy</h1>
            <p class="ck-lead ck-lead-tight">
              Restrict which MCP tools agents in this workspace may invoke.
              <code>inherit</code> falls back to the global allowlist; <code>allowlist</code>
              and <code>denylist</code> override it.
            </p>
          </div>
        </div>

        <.form for={@form} phx-submit="submit" class="ck-card mt-6 flex flex-col gap-4">
          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Mode</label>
            <select name="policy[mode]" class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white">
              <%= for m <- @modes do %>
                <option value={m} selected={@form[:mode].value == m}>{m}</option>
              <% end %>
            </select>
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-300 mb-1">Tool names (one per line)</label>
            <textarea
              name="policy[tools]"
              rows="8"
              placeholder="ck_validate&#10;ck_finding&#10;ck_context"
              class="w-full rounded-lg border border-white/10 bg-zinc-900 px-4 py-2 text-white font-mono"
            >{@form[:tools].value || ""}</textarea>
            <p class="mt-1 text-xs text-zinc-500">Used by <code>allowlist</code> and <code>denylist</code> modes. Ignored under <code>inherit</code>.</p>
          </div>

          <%= if @error do %>
            <p class="ck-note ck-note-danger">{@error}</p>
          <% end %>

          <%= if @saved do %>
            <p class="ck-note ck-note-success">Saved.</p>
          <% end %>

          <button type="submit" class="ck-btn ck-btn-primary self-start">Save policy</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  # ── Private ────────────────────────────────────────────────────────

  defp parse_tools(raw) when is_binary(raw) do
    raw
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_tools(_), do: []

  defp check_workspace_access(%Workspace{org_id: nil}, _), do: {:error, "Workspace is not bound to an org."}

  defp check_workspace_access(%Workspace{org_id: ws_org}, %{current_org_id: org_id, current_membership: m})
       when is_integer(ws_org) and ws_org == org_id do
    if m && Accounts.role_at_least?(m.role, "admin"),
      do: :ok,
      else: {:error, "Admin or owner role required."}
  end

  defp check_workspace_access(_, _), do: {:error, "Workspace belongs to a different organization."}

  defp redirect_with_flash(socket, kind, msg, path) do
    socket
    |> Phoenix.LiveView.put_flash(kind, msg)
    |> Phoenix.LiveView.push_navigate(to: path)
  end
end
