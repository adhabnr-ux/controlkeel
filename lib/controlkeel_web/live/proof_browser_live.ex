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
    case parse_int(id) do
      nil ->
        {:noreply,
         socket
         |> assign(:page_title, "Proof not found")
         |> assign(:proof, nil)
         |> assign(:memory_hits, [])}

      parsed_id ->
        case Mission.get_proof_bundle_with_context(parsed_id) do
          nil ->
            {:noreply,
             socket
             |> assign(:page_title, "Proof not found")
             |> assign(:proof, nil)
             |> assign(:memory_hits, [])}

          proof ->
            current_org_id = socket.assigns[:current_org_id]
            workspace_ids = org_workspace_ids(current_org_id)

            if current_org_id && proof.session.workspace_id not in workspace_ids do
              {:noreply,
               socket
               |> assign(:page_title, "Proof not found")
               |> assign(:proof, nil)
               |> assign(:memory_hits, [])}
            else
              memory_hits = related_memory_hits(proof)

              {:noreply,
               socket
               |> assign(:page_title, "Proof #{proof.id}")
               |> assign(:proof, proof)
               |> assign(:memory_hits, memory_hits)}
            end
        end
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
    <DashboardLayout.dashboard flash={@flash}>
      <section class="mx-auto w-[min(1180px,calc(100%-2rem))]">
        <div :if={@proof} class="space-y-8 mb-12">
          <.link
            navigate={~p"/proofs"}
            class="inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.14em] text-neutral-400 hover:text-neutral-200"
          >
            <.icon name="hero-arrow-left" class="w-3 h-3" /> Back to proofs
          </.link>

          <div class="flex items-center justify-between gap-4">
            <div class="space-y-1">
              <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
                Immutable proof snapshot
              </h2>
              <p class="text-[var(--ck-muted)]">
                Every proof bundle is a frozen audit artifact for a single task version.
              </p>
            </div>

            <.link
              navigate={~p"/missions/#{@proof.session_id}"}
              class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)] border-[var(--ck-muted)] border rounded-md px-3 py-2 hover:bg-[var(--ck-lime)]/10"
            >
              Open mission
            </.link>
          </div>
        </div>

        <div :if={!@proof} class="flex flex-col mt-28 items-center gap-4 text-center">
          <div>
            <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-tight font-sans font-semibold">
              Proof not found
            </h1>
          </div>

          <p class="text-lg text-zinc-400">
            No proof bundle exists with this identifier.
          </p>
          <.link
            navigate={~p"/proofs"}
            class="rounded-md border border-white/10 bg-black/40 px-5 py-2 text-xs font-semibold uppercase tracking-[0.1em] text-lime-400 transition hover:border-lime-400 inline-flex items-center gap-2"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Browse proofs
          </.link>
        </div>

        <div :if={@proof} class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4">
          <div class="rounded-2xl border border-[var(--ck-stroke)]  p-6 shadow-[0_24px_80px_rgba(0,0,0,0.22)] backdrop-blur-[18px]">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
              Task
            </p>
            <strong>{@proof.task.title}</strong>
          </div>
          <div class="rounded-2xl border border-[var(--ck-stroke)]  p-6 shadow-[0_24px_80px_rgba(0,0,0,0.22)] backdrop-blur-[18px]">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
              Version
            </p>
            <strong>v{@proof.version}</strong>
          </div>
          <div class="rounded-2xl border border-[var(--ck-stroke)]  p-6 shadow-[0_24px_80px_rgba(0,0,0,0.22)] backdrop-blur-[18px]">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
              Risk score
            </p>
            <strong>{@proof.risk_score}</strong>
          </div>
          <div class="rounded-2xl border border-[var(--ck-stroke)]  p-6 shadow-[0_24px_80px_rgba(0,0,0,0.22)] backdrop-blur-[18px]">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
              Deploy ready
            </p>
            <strong>{if @proof.deploy_ready, do: "Yes", else: "No"}</strong>
          </div>
        </div>

        <div
          :if={@proof}
          class="mt-6"
        >
          <div class="rounded-2xl border border-[var(--ck-stroke)] p-6 shadow-[0_24px_80px_rgba(0,0,0,0.22)] backdrop-blur-[18px]">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)] mb-2">
              Snapshot
            </p>
            <div class="grid grid-cols-2 gap-4 max-[900px]:grid-cols-1">
              <div>
                <h3>Mission</h3>
                <p class="text-[var(--ck-muted)]">{@proof.session.title}</p>
              </div>
              <div>
                <h3>Generated</h3>
                <p class="text-[var(--ck-muted)]">
                  {format_datetime(@proof.generated_at, "Not recorded")}
                </p>
              </div>
              <div>
                <h3>Open findings</h3>
                <p class="text-[var(--ck-muted)]">{@proof.open_findings_count}</p>
              </div>
              <div>
                <h3>Blocked findings</h3>
                <p class="text-[var(--ck-muted)]">{@proof.blocked_findings_count}</p>
              </div>
              <div>
                <h3>Domain pack</h3>
                <p class="text-[var(--ck-muted)]">
                  {format_domain_pack(get_in(@proof.session.execution_brief || %{}, ["domain_pack"]))}
                </p>
              </div>
            </div>

            <p class="mt-6 text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
              Compliance attestations
            </p>
            <ul class="m-0 grid gap-4 p-0 list-none">
              <%= for attestation <- List.wrap(@proof.bundle["compliance_attestations"]) do %>
                <li>
                  {format_domain_pack(attestation["pack"])}: {attestation["status"]} ({attestation[
                    "blocked_count"
                  ]} blocked)
                </li>
              <% end %>
            </ul>

            <div class="mt-6 space-y-2">
              <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
                Rollback instructions
              </p>

              <pre class="m-0 rounded-2xl border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.03)] w-fit p-4 font-mono text-sm leading-relaxed text-[var(--ck-sand)] whitespace-pre-wrap break-words">{@proof.bundle["rollback_instructions"]}</pre>
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 mt-6 gap-4">
              <div class="space-y-2">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
                  Related memory
                </p>

                <div class="rounded-2xl border border-[var(--ck-stroke)] p-4">
                  <%= if @memory_hits == [] do %>
                    <p class="text-[var(--ck-muted)]">No related memory hits for this task yet.</p>
                  <% else %>
                    <ul class="m-0 grid gap-4 p-0 list-none">
                      <%= for hit <- @memory_hits do %>
                        <li>
                          <strong>{hit.title}</strong>
                          <p class="text-[var(--ck-muted)]">{hit.summary}</p>
                        </li>
                      <% end %>
                    </ul>
                  <% end %>
                </div>
              </div>

              <div class="space-y-2">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
                  Finding resolution summary
                </p>

                <div class="rounded-2xl border border-[var(--ck-stroke)] p-6 grid grid-cols-2 gap-4">
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
                      Approved
                    </p>
                    <strong>
                      {get_in(@proof.bundle, ["finding_resolution_summary", "approved"]) || 0}
                    </strong>
                  </div>
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
                      Resolved
                    </p>
                    <strong>
                      {get_in(@proof.bundle, ["finding_resolution_summary", "resolved"]) || 0}
                    </strong>
                  </div>
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
                      Open
                    </p>
                    <strong>
                      {get_in(@proof.bundle, ["finding_resolution_summary", "open"]) || 0}
                    </strong>
                  </div>
                  <div>
                    <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
                      Blocked
                    </p>
                    <strong>
                      {get_in(@proof.bundle, ["finding_resolution_summary", "blocked"]) || 0}
                    </strong>
                  </div>
                </div>
              </div>
            </div>

            <p class="mt-6 text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)]">
              Assessment summary
            </p>
            <div class="mt-4 grid grid-cols-2 gap-4 max-[900px]:grid-cols-1">
              <div class="rounded-xl border border-[var(--ck-stroke)] p-5">
                <div class="flex items-center justify-between mb-4">
                  <p class="text-xs font-semibold uppercase tracking-[0.14em]">
                    Surface verification
                  </p>
                  <% ver_status = bundle_get(@proof, ["verification_assessment", "status"]) %>
                  <span
                    :if={ver_status}
                    class={[
                      "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider",
                      verification_status_color(ver_status)
                    ]}
                  >
                    {ver_status}
                  </span>
                </div>
                <div class="flex items-baseline gap-2 mb-4">
                  <% ver_score = bundle_get(@proof, ["verification_assessment", "score"]) %>
                  <span class={[
                    "text-3xl font-bold tabular-nums",
                    verification_score_color(ver_score)
                  ]}>
                    {ver_score || "—"}
                  </span>
                  <span :if={ver_score} class="text-sm text-zinc-500">/ 100</span>
                  <span
                    :if={
                      bundle_get(@proof, ["verification_assessment", "verification_ready"]) == true
                    }
                    class="ml-auto inline-flex items-center gap-1 rounded-full border border-lime-500/40 bg-lime-500/10 px-2.5 py-0.5 text-xs font-semibold text-lime-400"
                  >
                    <.icon name="hero-check-circle" class="w-3.5 h-3.5" /> Ready
                  </span>
                </div>
                <% ver_evidence = bundle_get(@proof, ["verification_assessment", "evidence"], %{}) %>
                <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
                  <span class="text-zinc-400">Passed checks</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {ver_evidence["passed_checks"] || 0}
                  </span>
                  <span class="text-zinc-400">Task checks (strong)</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {ver_evidence["passed_task_checks"] || 0} / {ver_evidence[
                      "passed_strong_task_checks"
                    ] || 0}
                  </span>
                  <span class="text-zinc-400">Failed checks</span>
                  <span class="text-right font-medium tabular-nums text-red-400">
                    {ver_evidence["failed_task_checks"] || 0}
                  </span>
                  <span class="text-zinc-400">External regressions</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {ver_evidence["external_regressions"] || 0}
                  </span>
                </div>
              </div>

              <div class="rounded-xl border border-[var(--ck-stroke)] p-5">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] mb-4">
                  Task check counts
                </p>
                <% task_checks = bundle_get(@proof, ["task_checks"], %{}) %>
                <% ch_total = task_checks["total"] || 0 %>
                <% ch_passed = task_checks["passed"] || 0 %>
                <% ch_failed = task_checks["failed"] || 0 %>
                <% ch_warn = task_checks["warn"] || 0 %>
                <div class="flex items-baseline gap-2 mb-4">
                  <span class="text-3xl font-bold tabular-nums text-white">{ch_total}</span>
                  <span class="text-sm text-zinc-500">total</span>
                  <span class="ml-auto flex gap-3 text-sm tabular-nums">
                    <span class="text-lime-400">{ch_passed} passed</span>
                    <span class="text-red-400">{ch_failed} failed</span>
                    <span class="text-amber-400">{ch_warn} warn</span>
                  </span>
                </div>
                <% passed_pct = if ch_total > 0, do: round(ch_passed / ch_total * 100), else: 0 %>
                <% failed_pct = if ch_total > 0, do: round(ch_failed / ch_total * 100), else: 0 %>
                <div class="h-2 rounded-full bg-zinc-800 overflow-hidden mb-4">
                  <div class="h-full flex">
                    <div
                      style={"width: #{passed_pct}%"}
                      class="bg-lime-500 transition-all rounded-l-full"
                    >
                    </div>
                    <div style={"width: #{failed_pct}%"} class="bg-red-500 transition-all"></div>
                  </div>
                </div>
                <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
                  <span class="text-zinc-400">Passed strong</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {task_checks["passed_strong"] || 0}
                  </span>
                  <span class="text-zinc-400">Strongest proof</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {task_checks["strongest_proof_strength"] || "—"}
                  </span>
                  <span class="text-zinc-400">Hashed outputs</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {task_checks["hashed_outputs"] || 0}
                  </span>
                  <span class="text-zinc-400">Git refs</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {length(task_checks["git_shas"] || [])}
                  </span>
                </div>
              </div>

              <div class="rounded-xl border border-[var(--ck-stroke)] p-5">
                <div class="flex items-center justify-between mb-4">
                  <p class="text-xs font-semibold uppercase tracking-[0.14em]">
                    Context integrity
                  </p>
                  <% ctx = bundle_get(@proof, ["runtime_context_integrity"], %{}) %>
                  <span class={[
                    "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider",
                    context_status_color(ctx["status"])
                  ]}>
                    <.icon
                      name={
                        if ctx["status"] == "clean",
                          do: "hero-check-circle",
                          else: "hero-exclamation-triangle"
                      }
                      class="w-3.5 h-3.5"
                    />
                    {ctx["status"] || "Unknown"}
                  </span>
                </div>
                <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
                  <span class="text-zinc-400">Partial reads</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {ctx["partial_read_count"] || 0}
                  </span>
                  <span class="text-zinc-400">Compactions</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {ctx["compaction_count"] || 0}
                  </span>
                  <span :if={ctx["compaction_source"]} class="text-zinc-400">Compaction source</span>
                  <span
                    :if={ctx["compaction_source"]}
                    class="text-right font-medium tabular-nums text-white"
                  >
                    {ctx["compaction_source"]}
                  </span>
                </div>
                <div :if={ctx["latest_compaction_reason"]} class="mt-3 rounded-lg bg-zinc-900/50 p-3">
                  <p class="text-xs text-zinc-400 mb-1">Latest compaction</p>
                  <p class="text-sm text-zinc-300">{ctx["latest_compaction_reason"]}</p>
                </div>
              </div>

              <div class="rounded-xl border border-[var(--ck-stroke)] p-5">
                <div class="flex items-center justify-between mb-4">
                  <p class="text-xs font-semibold uppercase tracking-[0.14em]">
                    Deploy readiness
                  </p>
                  <span class={[
                    "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider",
                    deploy_badge_class(@proof.deploy_ready)
                  ]}>
                    <.icon
                      name={if @proof.deploy_ready, do: "hero-check-circle", else: "hero-x-circle"}
                      class="w-3.5 h-3.5"
                    />
                    {if @proof.deploy_ready, do: "Ready", else: "Not ready"}
                  </span>
                </div>
                <div class="flex items-center gap-3 mb-4">
                  <div class="flex-1">
                    <div class="flex justify-between text-sm mb-1">
                      <span class="text-zinc-400">Risk score</span>
                      <span class="font-medium tabular-nums">{@proof.risk_score}</span>
                    </div>
                    <div class="h-2 rounded-full bg-zinc-800 overflow-hidden">
                      <div
                        style={"width: #{risk_bar_width(@proof.risk_score)}%"}
                        class={[
                          "h-full rounded-full transition-all",
                          @proof.risk_score <= 0.3 && "bg-lime-500",
                          @proof.risk_score > 0.3 && @proof.risk_score <= 0.6 && "bg-amber-500",
                          @proof.risk_score > 0.6 && "bg-red-500"
                        ]}
                      >
                      </div>
                    </div>
                  </div>
                </div>
                <div class="grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm">
                  <span class="text-zinc-400">Validation gate</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {@proof.bundle["validation_gate"] || "—"}
                  </span>
                  <span class="text-zinc-400">Open findings</span>
                  <span class="text-right font-medium tabular-nums text-amber-400">
                    {@proof.open_findings_count}
                  </span>
                  <span class="text-zinc-400">Blocked findings</span>
                  <span class="text-right font-medium tabular-nums text-red-400">
                    {@proof.blocked_findings_count}
                  </span>
                  <span class="text-zinc-400">Compliance packs</span>
                  <span class="text-right font-medium tabular-nums text-white">
                    {length(List.wrap(@proof.bundle["compliance_attestations"]))}
                  </span>
                </div>
                <div
                  :if={gate = bundle_get(@proof, ["security_workflow", "release_gate_decision"])}
                  class="mt-3"
                >
                  <span class={[
                    "inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider",
                    gate == "ready" && "border-lime-500/40 bg-lime-500/10 text-lime-400",
                    gate == "blocked" && "border-red-500/40 bg-red-500/10 text-red-400"
                  ]}>
                    Release gate: {gate}
                  </span>
                </div>
              </div>
            </div>

            <details class="mt-6 group">
              <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--ck-lime)] cursor-pointer hover:text-lime-300 transition-colors list-none flex items-center gap-2">
                <.icon
                  name="hero-chevron-right"
                  class="w-3.5 h-3.5 group-open:rotate-90 transition-transform"
                /> Raw proof payload
              </summary>
              <pre class="m-0 mt-3 rounded-2xl border border-[var(--ck-stroke)] p-4 font-mono text-xs leading-relaxed text-[var(--ck-sand)] whitespace-pre-wrap break-words overflow-auto h-100">{Jason.encode!(@proof.bundle, pretty: true)}</pre>
            </details>
          </div>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  def render(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section class="mx-auto w-[min(1180px,calc(100%-2rem))]">
        <div class="space-y-1 mb-12">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Proof browser
          </h2>
          <p class="text-[var(--ck-muted)]">
            Review immutable task evidence, filter by readiness and risk, and jump back to the mission that generated each bundle.
          </p>
        </div>

        <div class="rounded-lg border border-[var(--ck-stroke)] bg-neutral-900">
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

            <div class="flex items-center justify-between">
              <p class="text-neutral-400 tracking-tight">
                <span class="text-[var(--ck-lime)] mr-1">{@browser.total_count}</span>
                total proof bundles found
              </p>

              <.link
                patch={~p"/proofs"}
                class="self-end rounded-md border border-white/10 bg-black/40 px-4 py-3 text-xs font-semibold uppercase tracking-[0.1em] text-zinc-400 transition hover:border-red-500/40 hover:text-red-400 text-center"
              >
                Reset all
              </.link>
            </div>
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
                        <% ver = bundle_get(proof, ["verification_assessment"], %{}) %>
                        <div :if={ver["score"] || ver["status"]} class="mt-2 flex items-center gap-2">
                          <span class={[
                            "text-sm font-semibold tabular-nums",
                            verification_score_color(ver["score"])
                          ]}>
                            {ver["score"] || "—"}
                          </span>
                          <span class={[
                            "inline-flex rounded-full border px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider",
                            verification_status_color(ver["status"])
                          ]}>
                            {ver["status"] || "n/a"}
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
                        <% tc = bundle_get(proof, ["task_checks"], %{}) %>
                        <% t_total = tc["total"] || 0 %>
                        <% t_passed = tc["passed"] || 0 %>
                        <div :if={t_total > 0} class="mt-2">
                          <div class="flex items-center justify-between text-[11px] text-zinc-500 mb-1">
                            <span>Checks</span>
                            <span>{t_passed}/{t_total} passed</span>
                          </div>
                          <div class="h-1.5 rounded-full bg-zinc-800 overflow-hidden">
                            <div
                              style={"width: #{if t_total > 0, do: round(t_passed / t_total * 100), else: 0}%"}
                              class="bg-lime-500 h-full rounded-full transition-all"
                            >
                            </div>
                          </div>
                        </div>
                      </td>

                      <td class="px-2 py-6 text-right align-top">
                        <div class="flex justify-end gap-2 font-semibold text-sm">
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
    </DashboardLayout.dashboard>
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
      "deploy_ready" => if(filters.deploy_ready != nil, do: to_string(filters.deploy_ready)),
      "risk_tier" => filters.risk_tier
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

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

  defp bundle_get(proof, keys, default \\ nil) do
    if proof, do: get_in(proof.bundle || %{}, keys) || default, else: default
  end

  defp verification_score_color(score) when is_integer(score) do
    cond do
      score >= 80 -> "text-lime-400"
      score >= 50 -> "text-amber-400"
      true -> "text-red-400"
    end
  end

  defp verification_score_color(_), do: "text-zinc-400"

  defp verification_status_color("strong"), do: "border-lime-500/40 bg-lime-500/10 text-lime-400"

  defp verification_status_color("moderate"),
    do: "border-amber-500/40 bg-amber-500/10 text-amber-400"

  defp verification_status_color("weak"), do: "border-red-500/40 bg-red-500/10 text-red-400"
  defp verification_status_color(_), do: "border-zinc-500/40 bg-zinc-500/10 text-zinc-400"

  defp context_status_color("clean"), do: "border-lime-500/40 bg-lime-500/10 text-lime-400"
  defp context_status_color("degraded"), do: "border-red-500/40 bg-red-500/10 text-red-400"
  defp context_status_color(_), do: "border-zinc-500/40 bg-zinc-500/10 text-zinc-400"

  defp deploy_badge_class(true), do: "border-lime-500/40 bg-lime-500/10 text-lime-400"
  defp deploy_badge_class(_), do: "border-yellow-500/40 bg-yellow-500/10 text-yellow-400"

  defp risk_bar_width(nil), do: 0
  defp risk_bar_width(score) when is_float(score), do: min(round(score * 100), 100)
  defp risk_bar_width(_), do: 0

  defp org_workspace_ids(nil), do: []

  defp org_workspace_ids(org_id) when is_integer(org_id) do
    org_id
    |> ControlKeel.Accounts.list_workspaces_for_org()
    |> Enum.map(& &1.id)
  end
end
