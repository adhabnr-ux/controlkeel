defmodule ControlKeelWeb.ProofBrowserLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Memory
  alias ControlKeel.Mission

  @risk_tiers ~w(low moderate high critical)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Proof Browser")
     |> assign(:proof, nil)
     |> assign(:browser, empty_browser())
     |> assign(:memory_hits, [])
     |> assign(:risk_tiers, @risk_tiers)
     |> assign(:session_options, Mission.list_recent_sessions(30, nil))
     |> assign(:form, to_form(%{}, as: :filters))}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Mission.get_proof_bundle_with_context(String.to_integer(id)) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Proof bundle not found.")
         |> push_navigate(to: ~p"/proofs")}

      proof ->
        memory_hits = related_memory_hits(proof)

        {:noreply,
         socket
         |> assign(:page_title, "Proof #{proof.id}")
         |> assign(:proof, proof)
         |> assign(:memory_hits, memory_hits)}
    end
  end

  def handle_params(params, _uri, socket) do
    workspace_ids = org_workspace_ids(socket.assigns[:current_org_id])

    params =
      if workspace_ids != [],
        do: Map.put(params, "workspace_ids", workspace_ids),
        else: params

    browser = Mission.browse_proof_bundles(params)

    {:noreply,
     socket
     |> assign(:page_title, "Proof Browser")
     |> assign(:proof, nil)
     |> assign(:memory_hits, [])
     |> assign(:browser, browser)
     |> assign(:form, to_form(browser_form_params(browser.filters), as: :filters))}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: ~p"/proofs?#{filter_params(filters)}")}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <div class="ck-section-header">
          <div>
            <p class="ck-kicker">Proof browser</p>
            <h1 class="ck-section-title">Immutable proof snapshot</h1>
            <p class="ck-lead ck-lead-tight">
              Every proof bundle is a frozen audit artifact for a single task version.
            </p>
          </div>
          <div class="ck-badge-stack">
            <.link navigate={~p"/proofs"} class="ck-link">Back to proofs</.link>
            <.link navigate={~p"/missions/#{@proof.session_id}"} class="ck-link">Open mission</.link>
          </div>
        </div>

        <div class="ck-stat-grid">
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Task</p>
            <strong>{@proof.task.title}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Version</p>
            <strong>v{@proof.version}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Risk score</p>
            <strong>{@proof.risk_score}</strong>
          </div>
          <div class="ck-card ck-stat-card">
            <p class="ck-mini-label">Deploy ready</p>
            <strong>{if @proof.deploy_ready, do: "Yes", else: "No"}</strong>
          </div>
        </div>

        <div class="ck-grid ck-grid-dashboard">
          <div class="ck-card">
            <p class="ck-mini-label">Snapshot</p>
            <div class="ck-brief-grid">
              <div>
                <h3>Mission</h3>
                <p class="ck-note">{@proof.session.title}</p>
              </div>
              <div>
                <h3>Generated</h3>
                <p class="ck-note">{format_datetime(@proof.generated_at)}</p>
              </div>
              <div>
                <h3>Open findings</h3>
                <p class="ck-note">{@proof.open_findings_count}</p>
              </div>
              <div>
                <h3>Blocked findings</h3>
                <p class="ck-note">{@proof.blocked_findings_count}</p>
              </div>
              <div>
                <h3>Domain pack</h3>
                <p class="ck-note">
                  {format_domain_pack(get_in(@proof.session.execution_brief || %{}, ["domain_pack"]))}
                </p>
              </div>
            </div>

            <p class="ck-mini-label" style="margin-top: 1.5rem;">Compliance attestations</p>
            <ul class="ck-mini-list">
              <%= for attestation <- List.wrap(@proof.bundle["compliance_attestations"]) do %>
                <li>
                  {format_domain_pack(attestation["pack"])}: {attestation["status"]} ({attestation[
                    "blocked_count"
                  ]} blocked)
                </li>
              <% end %>
            </ul>

            <p class="ck-mini-label" style="margin-top: 1.5rem;">Rollback instructions</p>
            <pre class="ck-code-block">{@proof.bundle["rollback_instructions"]}</pre>

            <p class="ck-mini-label" style="margin-top: 1.5rem;">Proof payload</p>
            <pre class="ck-code-block">{Jason.encode!(@proof.bundle, pretty: true)}</pre>
          </div>

          <div class="ck-side-stack">
            <div class="ck-card">
              <p class="ck-mini-label">Related memory</p>
              <%= if @memory_hits == [] do %>
                <p class="ck-note">No related memory hits for this task yet.</p>
              <% else %>
                <ul class="ck-mini-list">
                  <%= for hit <- @memory_hits do %>
                    <li>
                      <strong>{hit.title}</strong>
                      <p class="ck-note">{hit.summary}</p>
                    </li>
                  <% end %>
                </ul>
              <% end %>
            </div>

            <div class="ck-card">
              <p class="ck-mini-label">Finding resolution summary</p>
              <div class="ck-stat-grid">
                <div class="ck-stat-card">
                  <p class="ck-mini-label">Approved</p>
                  <strong>
                    {get_in(@proof.bundle, ["finding_resolution_summary", "approved"]) || 0}
                  </strong>
                </div>
                <div class="ck-stat-card">
                  <p class="ck-mini-label">Resolved</p>
                  <strong>
                    {get_in(@proof.bundle, ["finding_resolution_summary", "resolved"]) || 0}
                  </strong>
                </div>
                <div class="ck-stat-card">
                  <p class="ck-mini-label">Open</p>
                  <strong>
                    {get_in(@proof.bundle, ["finding_resolution_summary", "open"]) || 0}
                  </strong>
                </div>
                <div class="ck-stat-card">
                  <p class="ck-mini-label">Blocked</p>
                  <strong>
                    {get_in(@proof.bundle, ["finding_resolution_summary", "blocked"]) || 0}
                  </strong>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell ck-shell-tight">
        <div class="space-y-1">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Proof browser
          </h2>
          <p class="text-[var(--ck-muted)]">
            Review immutable task evidence, filter by readiness and risk, and jump back to the mission that generated each bundle.
          </p>
        </div>

        <div class="mt-8 rounded-lg border border-[var(--ck-stroke)] bg-neutral-900">
          <div class="space-y-4 p-4">
            <form id="proof-filters" phx-change="filter" class="grid gap-4 xl:grid-cols-5">
              <div class="space-y-4">
                <label
                  for="filters-q"
                  class="text-xs uppercase tracking-[0.28em]"
                >
                  Search
                </label>
                <input
                  id="filters-q"
                  name="filters[q]"
                  type="text"
                  value={@form[:q].value}
                  placeholder="Mission or task..."
                  phx-debounce="300"
                  class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white placeholder:text-slate-500 focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                />
              </div>

              <div class="space-y-2">
                <label
                  for="filters-session_id"
                  class="text-xs uppercase tracking-[0.28em]"
                >
                  Mission
                </label>
                <select
                  id="filters-session_id"
                  name="filters[session_id]"
                  class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                >
                  <option value="">All missions</option>
                  <%= for session_option <- @session_options do %>
                    <option
                      value={session_option.id}
                      selected={to_string(@form[:session_id].value) == to_string(session_option.id)}
                    >
                      {session_option.title}
                    </option>
                  <% end %>
                </select>
              </div>

              <div class="space-y-2">
                <label
                  for="filters-task_id"
                  class="text-xs uppercase tracking-[0.28em]"
                >
                  Task ID
                </label>
                <input
                  id="filters-task_id"
                  name="filters[task_id]"
                  type="text"
                  value={@form[:task_id].value}
                  placeholder="Task id"
                  class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white placeholder:text-slate-500 focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                />
              </div>

              <div class="space-y-2">
                <label
                  for="filters-deploy_ready"
                  class="text-xs uppercase tracking-[0.28em]"
                >
                  Deploy ready
                </label>
                <select
                  id="filters-deploy_ready"
                  name="filters[deploy_ready]"
                  class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                >
                  <option value="">All</option>
                  <option value="true" selected={@form[:deploy_ready].value == "true"}>Yes</option>
                  <option value="false" selected={@form[:deploy_ready].value == "false"}>No</option>
                </select>
              </div>

              <div class="space-y-2">
                <label
                  for="filters-risk_tier"
                  class="text-xs uppercase tracking-[0.28em]"
                >
                  Risk tier
                </label>
                <select
                  id="filters-risk_tier"
                  name="filters[risk_tier]"
                  class="w-full rounded-md border border-white/10 bg-black/40 px-4 py-3 text-sm text-white focus:border-[var(--ck-lime)] focus:ring-2 focus:ring-[rgba(196,240,66,0.15)] focus:outline-none"
                >
                  <option value="">All tiers</option>
                  <%= for tier <- @risk_tiers do %>
                    <option value={tier} selected={@form[:risk_tier].value == tier}>
                      {String.capitalize(tier)}
                    </option>
                  <% end %>
                </select>
              </div>
            </form>

            <p class="text-neutral-400 tracking-tight">
              <span class="text-[var(--ck-lime)] mr-1">{@browser.total_count}</span>
              total proof bundles found
            </p>
          </div>

          <div class="overflow-x-auto w-full">
            <div class="overflow-hidden border border-white/10 bg-black/30">
              <div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-white/10">
                  <thead class="bg-white/5">
                    <tr>
                      <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                        Task
                      </th>

                      <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                        Version
                      </th>

                      <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                        Risk
                      </th>

                      <th class="px-8 py-6 text-left text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                        Readiness
                      </th>

                      <th class="px-8 py-6 text-right text-xs font-semibold uppercase tracking-[0.15em] text-zinc-300">
                        Actions
                      </th>
                    </tr>
                  </thead>

                  <tbody class="divide-y divide-white/5">
                    <tr :if={@browser.entries == []}>
                      <td colspan="5" class="px-8 py-12 text-center text-sm text-zinc-500">
                        No proof bundles match the current filters.
                      </td>
                    </tr>
                    <tr
                      :for={proof <- @browser.entries}
                      class="transition hover:bg-white/[0.02]"
                    >
                      <td class="px-8 py-6 align-top">
                        <div>
                          <p class="font-bold text-white">
                            {proof.task.title}
                          </p>

                          <p class="mt-2 max-w-md text-sm text-zinc-400">
                            {proof.session.title}
                          </p>
                        </div>
                      </td>

                      <td class="px-8 py-6 align-top">
                        <div>
                          <p class="font-semibold text-white">
                            v{proof.version}
                          </p>

                          <p class="mt-2 text-xs uppercase tracking-wider text-lime-400">
                            {proof.status}
                          </p>
                        </div>
                      </td>

                      <td class="px-8 py-6 align-top">
                        <div class="flex items-center gap-3">
                          <span class={[
                            "inline-flex rounded-full border px-3 py-1 text-xs font-semibold uppercase tracking-wider",
                            proof.session.risk_tier == "low" &&
                              "border-lime-500/40 bg-lime-500/10 text-lime-400",
                            proof.session.risk_tier == "moderate" &&
                              "border-cyan-500/40 bg-cyan-500/10 text-cyan-400",
                            proof.session.risk_tier == "high" &&
                              "border-red-500/40 bg-red-500/10 text-red-400"
                          ]}>
                            {proof.session.risk_tier}
                          </span>

                          <span class="inline-flex rounded-full border border-white/10 px-4 py-2 text-sm text-zinc-300">
                            {proof.risk_score}
                          </span>
                        </div>
                      </td>

                      <td class="px-8 py-6 align-top">
                        <div class="flex items-center gap-4">
                          <span class={[
                            "inline-flex h-8 w-8 items-center justify-center rounded-full border text-xs",
                            proof.deploy_ready &&
                              "border-lime-500/40 text-lime-400",
                            !proof.deploy_ready &&
                              "border-yellow-500/40 text-yellow-400"
                          ]}>
                            {proof.risk_score}
                          </span>

                          <span class={[
                            "text-sm",
                            proof.deploy_ready &&
                              "text-white",
                            !proof.deploy_ready &&
                              "text-zinc-300"
                          ]}>
                            {if proof.deploy_ready,
                              do: "Certified ready",
                              else: "Review required"}
                          </span>
                        </div>
                      </td>

                      <td class="px-2 py-6 text-right align-top">
                        <div class="flex justify-end gap-4 font-semibold text-sm">
                          <.link
                            navigate={~p"/missions/#{proof.session_id}"}
                            class="text-zinc-400 transition hover:text-white border px-2 py-1 rounded-md"
                          >
                            Mission
                          </.link>

                          <.link
                            navigate={~p"/proofs/#{proof.id}"}
                            class="text-lime-400 transition hover:text-lime-300 border px-2 py-1 rounded-md"
                          >
                            View
                          </.link>
                        </div>
                      </td>
                    </tr>
                  </tbody>
                </table>
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
                          ~p"/proofs?#{Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page - 1})}"
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
                          ~p"/proofs?#{Map.merge(browser_form_params(@browser.filters), %{"page" => @browser.page + 1})}"
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
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp related_memory_hits(proof) do
    related = Memory.list_related_to_task(proof.task_id, 5)

    if related != [] do
      related
    else
      Memory.search(proof.task.title,
        session_id: proof.session_id,
        task_id: proof.task_id,
        top_k: 5
      ).entries
    end
  end

  defp browser_form_params(filters) do
    %{
      "q" => filters.q,
      "session_id" => filters.session_id,
      "task_id" => filters.task_id,
      "deploy_ready" => filters.deploy_ready,
      "risk_tier" => filters.risk_tier
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp filter_params(filters) do
    filters
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp empty_browser do
    %{entries: [], filters: %{page: 1}, total_count: 0, total_pages: 1, page: 1, page_size: 20}
  end

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(pack) when pack in ["baseline", "cost"], do: String.capitalize(pack)
  defp format_domain_pack(pack), do: Intent.pack_label(pack)
  defp format_datetime(nil), do: "Not recorded"
  defp format_datetime(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp org_workspace_ids(nil), do: []

  defp org_workspace_ids(org_id) when is_integer(org_id) do
    org_id
    |> ControlKeel.Accounts.list_workspaces_for_org()
    |> Enum.map(& &1.id)
  end
end
