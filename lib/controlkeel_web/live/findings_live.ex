defmodule ControlKeelWeb.FindingsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission
  alias ControlKeelWeb.FindingComponents

  @severities ~w(critical high medium low)
  @statuses ~w(open blocked escalated approved rejected)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Findings")
     |> assign(:browser, empty_browser())
     |> assign(:categories, Mission.list_finding_categories())
     |> assign(:session_options, Mission.list_findings_browser_sessions())
     |> assign(:selected_finding, nil)
     |> assign(:selected_fix, nil)
     |> assign(:reject_id, nil)
     |> assign(:reject_reason, "")
     |> assign(:severities, @severities)
     |> assign(:statuses, @statuses)
     |> assign(:open_dropdown_id, nil)
     |> assign(:form, to_form(%{}, as: :filters))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    params = inject_org_workspace_ids(params, socket.assigns[:current_org_id])
    browser = Mission.browse_findings(params)

    selected_finding =
      case socket.assigns[:selected_finding] do
        %{id: id} ->
          Enum.find(browser.entries, &(&1.id == id)) || Mission.get_finding_with_context(id)

        _ ->
          nil
      end

    {:noreply,
     socket
     |> assign(:browser, browser)
     |> assign(:selected_finding, selected_finding)
     |> assign(:selected_fix, maybe_regenerate_fix(selected_finding))
     |> assign(:open_dropdown_id, nil)
     |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: findings_path(filter_params(filters)))}
  end

  @impl true
  def handle_event("toggle_dropdown", %{"id" => id}, socket) do
    current = socket.assigns.open_dropdown_id
    {:noreply, assign(socket, :open_dropdown_id, if(current == id, do: nil, else: id))}
  end

  @impl true
  def handle_event("close_dropdown", _params, socket) do
    {:noreply, assign(socket, :open_dropdown_id, nil)}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding(finding_id),
         {:ok, _updated} <- Mission.approve_finding(finding) do
      {:noreply,
       socket
       |> put_flash(:info, "Finding approved.")
       |> refresh_browser()}
    else
      _error ->
        {:noreply,
         socket
         |> assign(:open_dropdown_id, nil)
         |> put_flash(:error, "ControlKeel could not approve that finding.")}
    end
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:noreply,
     socket
     |> assign(:reject_id, id)
     |> assign(:reject_reason, "")
     |> assign(:open_dropdown_id, nil)}
  end

  @impl true
  def handle_event("set_reject_reason", %{"value" => reason}, socket) do
    {:noreply, assign(socket, :reject_reason, reason)}
  end

  @impl true
  def handle_event("confirm_reject", _params, socket) do
    id = socket.assigns.reject_id

    reason =
      socket.assigns.reject_reason |> String.trim() |> then(&if &1 == "", do: nil, else: &1)

    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding(finding_id),
         {:ok, _updated} <- Mission.reject_finding(finding, reason) do
      {:noreply,
       socket
       |> assign(:reject_id, nil)
       |> assign(:reject_reason, "")
       |> put_flash(:info, "Finding rejected.")
       |> refresh_browser()}
    else
      _error ->
        {:noreply, put_flash(socket, :error, "ControlKeel could not reject that finding.")}
    end
  end

  @impl true
  def handle_event("cancel_reject", _params, socket) do
    {:noreply,
     socket
     |> assign(:reject_id, nil)
     |> assign(:reject_reason, "")
     |> assign(:open_dropdown_id, nil)}
  end

  @impl true
  def handle_event("view_fix", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Mission.get_finding_with_context(finding_id) do
      fix = Mission.auto_fix_for_finding(finding)
      emit_autofix_event(:viewed, finding, fix)

      {:noreply,
       socket
       |> assign(:open_dropdown_id, nil)
       |> assign(:selected_finding, finding)
       |> assign(:selected_fix, fix)}
    else
      _error ->
        {:noreply,
         socket
         |> assign(:open_dropdown_id, nil)
         |> put_flash(:error, "ControlKeel could not load that fix.")}
    end
  end

  @impl true
  def handle_event("copy_fix_prompt", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <- socket.assigns.selected_finding,
         %{"agent_prompt" => prompt} = fix <- socket.assigns.selected_fix,
         true <- is_binary(prompt) and prompt != "" do
      emit_autofix_event(:copied, finding, fix)

      {:noreply,
       socket
       |> push_event("copy-to-clipboard", %{text: prompt})
       |> put_flash(:info, "Fix prompt copied to the clipboard.")}
    else
      _error -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_fix", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_finding, nil)
     |> assign(:selected_fix, nil)
     |> assign(:open_dropdown_id, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16">
        <div class="space-y-1 mb-12">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Findings browser
          </h2>
          <p class="text-[var(--ck-muted)]">
            Filter, approve, reject, and inspect guided fixes without leaving the governed ControlKeel workflow.
          </p>
        </div>

        <div class="rounded-lg border border-[var(--ck-stroke)] bg-neutral-900">
          <div class="space-y-4 p-4">
            <.form for={@form} phx-change="filter">
              <div class="grid gap-4 xl:grid-cols-5">
                <div class="space-y-2">
                  <label for="filters-q" class="text-xs uppercase tracking-[0.28em]">Search</label>
                  <input
                    id="filters-q"
                    name="filters[q]"
                    type="text"
                    value={@form[:q].value}
                    placeholder="Rule, title, session..."
                    phx-debounce="300"
                    class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white placeholder:text-slate-500 focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                  />
                </div>
                <div class="space-y-2">
                  <label for="filters-severity" class="text-xs uppercase tracking-[0.28em]">
                    Severity
                  </label>
                  <select
                    id="filters-severity"
                    name="filters[severity]"
                    class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                  >
                    <option value="">All severities</option>
                    <%= for s <- @severities do %>
                      <option value={s} selected={@form[:severity].value == s}>
                        {String.capitalize(s)}
                      </option>
                    <% end %>
                  </select>
                </div>
                <div class="space-y-2">
                  <label for="filters-status" class="text-xs uppercase tracking-[0.28em]">
                    Status
                  </label>
                  <select
                    id="filters-status"
                    name="filters[status]"
                    class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                  >
                    <option value="">All statuses</option>
                    <%= for s <- @statuses do %>
                      <option value={s} selected={@form[:status].value == s}>
                        {String.capitalize(s)}
                      </option>
                    <% end %>
                  </select>
                </div>
                <div class="space-y-2">
                  <label for="filters-category" class="text-xs uppercase tracking-[0.28em]">
                    Category
                  </label>
                  <select
                    id="filters-category"
                    name="filters[category]"
                    class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                  >
                    <option value="">All categories</option>
                    <%= for c <- @categories do %>
                      <option value={c} selected={@form[:category].value == c}>
                        {String.capitalize(c)}
                      </option>
                    <% end %>
                  </select>
                </div>
                <div class="space-y-2">
                  <label for="filters-session_id" class="text-xs uppercase tracking-[0.28em]">
                    Mission
                  </label>
                  <select
                    id="filters-session_id"
                    name="filters[session_id]"
                    class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                  >
                    <option value="">All missions</option>
                    <%= for {label, id} <- session_filter_options(@session_options) do %>
                      <option
                        value={id}
                        selected={to_string(@form[:session_id].value) == to_string(id)}
                      >
                        {label}
                      </option>
                    <% end %>
                  </select>
                </div>
              </div>
            </.form>

            <div class="flex items-center justify-between">
              <p class="text-neutral-400 tracking-tight">
                <span class="text-[var(--ck-lime)] mr-1">{@browser.total_count}</span> total findings
              </p>

              <.link
                patch={findings_path(%{})}
                class="self-end rounded-md border border-white/10 bg-black/40 px-4 py-3 text-xs font-semibold uppercase tracking-[0.1em] text-zinc-400 transition hover:border-red-500/40 hover:text-red-400 text-center"
              >
                Reset all
              </.link>
            </div>
          </div>

          <div class="overflow-x-auto w-full">
            <div class="overflow-hidden border-t border-white/10 bg-black/30">
              <table class="min-w-full divide-y divide-white/10">
                <thead class="bg-white/5">
                  <tr>
                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                      Finding
                    </th>
                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                      Mission
                    </th>
                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                      Status
                    </th>
                    <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                      Rule
                    </th>
                    <th class="px-8 py-6 text-right text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-white/5">
                  <tr :if={@browser.entries == []}>
                    <td colspan="5" class="px-8 py-12 text-center text-sm text-zinc-500">
                      No findings match the current filters.
                    </td>
                  </tr>
                  <tr
                    :for={finding <- @browser.entries}
                    class="transition hover:bg-white/[0.02]"
                  >
                    <td class="px-8 py-6 align-top">
                      <div>
                        <p class="font-bold text-white">{finding.title}</p>
                        <p class="mt-2 max-w-md text-sm text-zinc-400">{finding.plain_message}</p>
                      </div>
                    </td>
                    <td class="px-8 py-6 align-top">
                      <div>
                        <.link
                          navigate={~p"/missions/#{finding.session_id}"}
                          class="text-xs font-semibold tracking-[0.14em] text-[var(--ck-lime)] uppercase hover:underline"
                        >
                          {finding.session.title}
                        </.link>
                        <p class="mt-2 text-sm text-zinc-400">{finding.session.workspace.name}</p>
                      </div>
                    </td>
                    <td class="px-8 py-6 align-top">
                      <div class="flex flex-wrap items-center gap-2">
                        <span class={[pill_base(), severity_colors(finding.severity)]}>
                          {finding.severity}
                        </span>
                        <span class={[pill_base(), "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"]}>
                          {finding.status}
                        </span>
                      </div>
                    </td>
                    <td class="px-8 py-6 align-top">
                      <div>
                        <p class="font-bold text-white">{finding.rule_id}</p>
                        <p class="mt-2 text-sm text-zinc-400">{finding.category}</p>
                      </div>
                    </td>
                    <td class="px-2 py-6 text-right align-top">
                      <%= if @reject_id == to_string(finding.id) do %>
                        <div class="flex items-center justify-end gap-1">
                          <input
                            type="text"
                            class="w-36 rounded-md border border-white/10 bg-black/40 px-3 py-2 text-sm text-white placeholder:text-slate-500 focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                            placeholder="Reason"
                            value={@reject_reason}
                            phx-keyup="set_reject_reason"
                            phx-key="Enter"
                            phx-click-away="cancel_reject"
                          />
                          <button
                            type="button"
                            class="rounded-md border border-white/10 bg-black px-3 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-lime-400 transition hover:border-lime-400"
                            phx-click="confirm_reject"
                          >
                            Confirm
                          </button>
                          <button
                            type="button"
                            class="rounded-md border border-white/10 bg-black px-3 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-zinc-400 transition hover:border-red-500/40 hover:text-red-400"
                            phx-click="cancel_reject"
                          >
                            Cancel
                          </button>
                        </div>
                      <% else %>
                        <div class="relative inline-flex">
                          <button
                            type="button"
                            class="flex items-center justify-center w-8 h-8 rounded-md border border-white/10 bg-black/40 hover:bg-white/10 text-zinc-400 hover:text-white transition-colors"
                            phx-click="toggle_dropdown"
                            phx-value-id={finding.id}
                          >
                            ⋮
                          </button>
                          <div
                            :if={@open_dropdown_id == to_string(finding.id)}
                            class="absolute right-0 top-full mt-1 z-50 min-w-[140px] rounded-lg border border-white/10 bg-neutral-900 shadow-2xl py-1"
                            phx-click-away="close_dropdown"
                          >
                            <button
                              type="button"
                              class="w-full text-left px-4 py-2 text-sm text-lime-400 hover:bg-white/5 transition-colors"
                              phx-click="approve"
                              phx-value-id={finding.id}
                            >
                              Approve
                            </button>
                            <button
                              type="button"
                              class="w-full text-left px-4 py-2 text-sm text-zinc-300 hover:bg-white/5 transition-colors"
                              phx-click="reject"
                              phx-value-id={finding.id}
                            >
                              Reject
                            </button>
                            <button
                              type="button"
                              class="w-full text-left px-4 py-2 text-sm text-zinc-300 hover:bg-white/5 transition-colors"
                              phx-click="view_fix"
                              phx-value-id={finding.id}
                            >
                              View fix
                            </button>
                          </div>
                        </div>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <div class="border-t border-white/10 bg-black/40 px-6 py-4">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div class="text-xs uppercase tracking-[0.15em] text-zinc-400">
                Page {@browser.page} of {@browser.total_pages}
              </div>
              <div class="flex gap-3">
                <%= if @browser.page > 1 do %>
                  <.link
                    patch={
                      findings_path(
                        Map.merge(browser_form_params(@browser.filters), %{
                          "page" => @browser.page - 1
                        })
                      )
                    }
                    class="rounded-md border border-white/10 bg-black px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-lime-400 transition hover:border-lime-400"
                  >
                    Previous
                  </.link>
                <% else %>
                  <span class="cursor-not-allowed rounded-md border border-white/10 bg-white/5 px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-zinc-600">
                    Previous
                  </span>
                <% end %>
                <%= if @browser.page < @browser.total_pages do %>
                  <.link
                    patch={
                      findings_path(
                        Map.merge(browser_form_params(@browser.filters), %{
                          "page" => @browser.page + 1
                        })
                      )
                    }
                    class="rounded-md border border-white/10 bg-black px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-lime-400 transition hover:border-lime-400"
                  >
                    Next
                  </.link>
                <% else %>
                  <span class="cursor-not-allowed rounded-md border border-white/10 bg-white/5 px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-zinc-600">
                    Next
                  </span>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <FindingComponents.autofix_panel
          :if={@selected_finding && @selected_fix}
          finding={@selected_finding}
          fix={@selected_fix}
          copy_event="copy_fix_prompt"
          close_event="close_fix"
        />
      </section>
    </Layouts.app>
    """
  end

  defp inject_org_workspace_ids(params, nil), do: params

  defp inject_org_workspace_ids(params, org_id) when is_integer(org_id) do
    workspace_ids =
      org_id
      |> ControlKeel.Accounts.list_workspaces_for_org()
      |> Enum.map(& &1.id)

    if workspace_ids == [], do: params, else: Map.put(params, "workspace_ids", workspace_ids)
  end

  defp pill_base do
    "inline-flex items-center px-3 py-1.5 text-sm rounded-full border border-[var(--ck-stroke)]"
  end

  defp severity_colors("critical"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp severity_colors("high"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp severity_colors("medium"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp severity_colors("low"), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
  defp severity_colors(_), do: "bg-white/5 text-white/70"

  defp refresh_browser(socket) do
    params =
      socket.assigns.browser.filters
      |> browser_form_params()
      |> inject_org_workspace_ids(socket.assigns[:current_org_id])

    browser = Mission.browse_findings(params)

    selected_finding =
      case socket.assigns.selected_finding do
        %{id: id} ->
          Enum.find(browser.entries, &(&1.id == id)) || Mission.get_finding_with_context(id)

        _ ->
          nil
      end

    socket
    |> assign(:browser, browser)
    |> assign(:selected_finding, selected_finding)
    |> assign(:selected_fix, maybe_regenerate_fix(selected_finding))
    |> assign(:open_dropdown_id, nil)
    |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))
  end

  defp maybe_regenerate_fix(nil), do: nil
  defp maybe_regenerate_fix(finding), do: Mission.auto_fix_for_finding(finding)

  defp filter_params(params) do
    params
    |> Enum.into(%{}, fn {key, value} -> {to_string(key), normalize_param_value(value)} end)
    |> Map.put("page", 1)
  end

  defp browser_form_params(filters) do
    %{
      "q" => filters.q || "",
      "severity" => filters.severity || "",
      "status" => filters.status || "",
      "category" => filters.category || "",
      "session_id" => filters.session_id || "",
      "page" => filters.page
    }
  end

  defp findings_path(params), do: ~p"/findings?#{prune_params(params)}"

  defp prune_params(params) do
    params
    |> Enum.reject(fn
      {"page", 1} -> true
      {_key, value} when value in [nil, ""] -> true
      _other -> false
    end)
    |> Map.new()
  end

  defp session_filter_options(sessions) do
    Enum.map(sessions, fn session ->
      workspace = (session.workspace && session.workspace.name) || "Workspace"
      {"#{session.title} (#{workspace})", session.id}
    end)
  end

  defp emit_autofix_event(action, finding, fix) do
    :telemetry.execute(
      [:controlkeel, :autofix, action],
      %{count: 1},
      %{
        finding_id: finding.id,
        session_id: finding.session_id,
        rule_id: finding.rule_id,
        supported: fix["supported"],
        fix_kind: fix["fix_kind"]
      }
    )
  end

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp normalize_param_value(nil), do: ""
  defp normalize_param_value(value), do: value

  defp empty_browser do
    %{
      entries: [],
      filters: %{q: nil, severity: nil, status: nil, category: nil, session_id: nil, page: 1},
      total_count: 0,
      total_pages: 1,
      page: 1,
      page_size: 20
    }
  end
end
