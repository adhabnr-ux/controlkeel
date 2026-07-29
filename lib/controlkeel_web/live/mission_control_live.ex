defmodule ControlKeelWeb.MissionControlLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Analytics
  alias ControlKeel.Agent.AutonomyLoop
  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeel.Observability
  alias ControlKeel.Proxy
  alias ControlKeelWeb.FindingComponents
  alias ControlKeelWeb.ShipReadiness

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Mission not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if session_accessible?(session, org_id) do
          if connected?(socket), do: schedule_refresh()
          project_root = socket.endpoint.config(:project_root) || File.cwd!()

          {:ok,
           socket
           |> assign(:page_title, session.title)
           |> assign(:project_root, project_root)
           |> assign(:launched, Map.get(params, "launched") == "1")
           |> assign(:selected_finding, nil)
           |> assign(:selected_fix, nil)
           |> safe_assign_session(session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Mission not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        if connected?(socket), do: schedule_refresh()
        project_root = socket.endpoint.config(:project_root) || File.cwd!()

        {:ok,
         socket
         |> assign(:page_title, session.title)
         |> assign(:project_root, project_root)
         |> assign(:launched, Map.get(params, "launched") == "1")
         |> assign(:selected_finding, nil)
         |> assign(:selected_fix, nil)
         |> safe_assign_session(session)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()

    case Mission.get_session_context(socket.assigns.session.id) do
      nil -> {:noreply, socket}
      session -> {:noreply, assign_session(socket, session)}
    end
  end

  @impl true
  def handle_event("view_fix", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{id: ^finding_id} = finding <-
           Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)) do
      fix = Mission.auto_fix_for_finding(finding)
      emit_autofix_event(:viewed, finding, fix)

      {:noreply,
       socket
       |> assign(:selected_finding, finding)
       |> assign(:selected_fix, fix)}
    else
      _error -> {:noreply, put_flash(socket, :error, "ControlKeel could not load that fix.")}
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
    {:noreply, socket |> assign(:selected_finding, nil) |> assign(:selected_fix, nil)}
  end

  @impl true
  def handle_event("approve_finding", %{"id" => id}, socket) do
    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.approve_finding(finding) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply,
           socket |> put_flash(:info, "Finding approved.") |> safe_assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not approve finding.")}
    end
  end

  @impl true
  def handle_event("reject_finding", params, socket) do
    id = params["id"]

    reason =
      params["reason"]
      |> then(&if is_binary(&1) and String.trim(&1) != "", do: String.trim(&1), else: nil)

    with {:ok, finding_id} <- parse_id(id),
         %{} = finding <- Enum.find(socket.assigns.session.findings, &(&1.id == finding_id)),
         {:ok, _updated} <- Mission.reject_finding(finding, reason) do
      case Mission.get_session_context(socket.assigns.session.id) do
        nil ->
          {:noreply, socket}

        session ->
          {:noreply,
           socket |> put_flash(:info, "Finding rejected.") |> safe_assign_session(session)}
      end
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not reject finding.")}
    end
  end

  @impl true
  def handle_event("generate_proof", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _proof} <- Mission.generate_proof_bundle(task_id),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply,
       socket |> put_flash(:info, "Proof bundle generated.") |> safe_assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not generate proof bundle.")}
    end
  end

  @impl true
  def handle_event("pause_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _result} <- Mission.pause_task(task_id, "mission_control"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply, socket |> put_flash(:info, "Task paused.") |> safe_assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not pause task.")}
    end
  end

  @impl true
  def handle_event("resume_task", %{"id" => id}, socket) do
    with {:ok, task_id} <- parse_id(id),
         {:ok, _result} <- Mission.resume_task(task_id, "mission_control"),
         session when not is_nil(session) <-
           Mission.get_session_context(socket.assigns.session.id) do
      {:noreply, socket |> put_flash(:info, "Task resumed.") |> safe_assign_session(session)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not resume task.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-[1180px] w-full px-4 pt-8 pb-16">
      <%= if @launched do %>
        <div class="p-6 rounded-3xl border border-white/10 bg-emerald-50 text-zinc-900 border-l-4 border-l-emerald-500 mb-6">
          <div class="flex items-start gap-4">
            <span class="text-2xl leading-none">✓</span>
            <div>
              <strong class="block mb-1">
                You're set — ControlKeel is governing this session
              </strong>
              <p class="text-sm text-zinc-600 mb-3">
                Attach your preferred client to start intercepting agent actions. OpenCode is the fastest MCP-plus-instructions path:
                <code class="font-mono bg-emerald-100 px-1.5 py-0.5 rounded text-sm">
                  controlkeel attach opencode
                </code>
              </p>
              <p class="text-sm text-zinc-600">
                Or validate content directly via the
                <a href="/policies" class="underline hover:text-emerald-700">Policy Studio</a>
                or REST API at <code class="font-mono bg-emerald-100 px-1.5 py-0.5 rounded text-sm">POST /api/v1/validate</code>.
              </p>
            </div>
          </div>
        </div>
      <% end %>
      <div class="space-y-1 mb-12">
        <h2 class="text-2xl font-semibold text-[var(--primary)] leading-6 tracking-wide uppercase">
          {@session.title}
        </h2>
        <p class="text-[var(--muted-foreground)]">
          {@session.objective}
        </p>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mt-5">
        <div class="p-5 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Primary agent
          </p>
          <strong>{@agent_label}</strong>
        </div>
        <div class="p-5 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Needs review
          </p>
          <strong>{@active_findings} finding{if @active_findings != 1, do: "s"}</strong>
        </div>
        <div class="p-5 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Compliance score
          </p>
          <div class="flex items-center gap-3">
            <svg
              viewBox="0 0 36 36"
              width="48"
              height="48"
              class="shrink-0 -rotate-90"
            >
              <circle cx="18" cy="18" r="15.9" fill="none" stroke="#e5e7eb" stroke-width="3.8" />
              <circle
                cx="18"
                cy="18"
                r="15.9"
                fill="none"
                stroke={donut_color(@compliance_score)}
                stroke-width="3.8"
                stroke-dasharray={"#{@compliance_score} #{100 - @compliance_score}"}
                stroke-linecap="round"
              />
            </svg>
            <strong>{@compliance_score}%</strong>
          </div>
        </div>
        <div class="p-5 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Budget spent
          </p>
          <strong>
            {format_currency(@session.spent_cents)} / {format_currency(@session.budget_cents)}
          </strong>
        </div>
        <div class="p-5 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-lg">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Proof bundles
          </p>
          <strong>{map_size(@latest_proofs)}</strong>
        </div>
      </div>

      <div
        id="mission-observability-panel"
        class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6"
      >
        <div class="flex flex-col md:flex-row md:items-center justify-between gap-4 mt-6 mb-4">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Session run observability
            </p>
            <h2 class="m-0 text-xl font-bold text-white">{@observability.health.label}</h2>
            <p class="text-sm text-zinc-400 mt-1.5">
              Compact local-first view of health, events, findings, gates, memory, proofs, and cost.
            </p>
          </div>
          <div class="flex flex-wrap gap-2 items-center">
            <span
              id="mission-observability-health"
              class={obs_health_pill_class(@observability.health.status)}
            >
              {@observability.health.status}
            </span>
            <.link
              id="mission-observability-open"
              navigate={~p"/observability/sessions/#{@session.id}"}
              class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 hover:text-lime-200 transition bg-transparent border-0 p-0 cursor-pointer"
            >
              Open run observability
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-5">
          <div
            id="mission-observability-budget"
            class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Budget health
            </p>
            <strong>{@observability.budget["decision"] || "unknown"}</strong>
            <p class="text-xs text-zinc-500 mt-1">
              {format_currency(@observability.budget["spent_cents"] || 0)} / {format_currency(
                @observability.budget["session_budget_cents"] || 0
              )} used
            </p>
          </div>
          <div
            id="mission-observability-findings"
            class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Findings
            </p>
            <strong>{@observability.findings.active} active</strong>
            <p class="text-xs text-zinc-500 mt-1">
              {@observability.findings.critical} critical · {@observability.findings.high} high · {@observability.findings.blocked} blocked
            </p>
          </div>
          <div
            id="mission-observability-gates"
            class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Gates
            </p>
            <strong>{@observability.gates.pending_reviews} pending</strong>
            <p class="text-xs text-zinc-500 mt-1">
              {@observability.gates.total_reviews} total review gates
            </p>
          </div>
          <div
            id="mission-observability-timeline"
            class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg"
          >
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Timeline
            </p>
            <strong>{@observability.timeline.count} events</strong>
            <p class="text-xs text-zinc-500 mt-1">
              {@observability.memory.records} memory · {@observability.proofs.count} proofs · {@observability.hosts_models_tools.invocations} calls
            </p>
          </div>
        </div>

        <div class="mt-4">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Recommendations
          </p>
          <ul id="mission-observability-recommendations" class="space-y-2 list-none p-0 m-0">
            <%= for recommendation <- Enum.take(@observability.recommendations, 3) do %>
              <li>{recommendation}</li>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
          Session metrics
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-5">
          <div class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Current funnel stage
            </p>
            <strong>{Analytics.stage_label(@session_metrics.funnel_stage)}</strong>
          </div>
          <div class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              First finding time
            </p>
            <strong>{format_duration(@session_metrics.time_to_first_finding_seconds)}</strong>
          </div>
          <div class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Total findings
            </p>
            <strong>{@session_metrics.total_findings}</strong>
          </div>
          <div class="p-5 rounded-3xl border border-white/10 bg-white/[0.03] shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
              Blocked findings
            </p>
            <strong>{@session_metrics.blocked_findings_total}</strong>
          </div>
        </div>
      </div>

      <ShipReadiness.ship_readiness
        verdict={@ship_verdict}
        improvement_loop={@improvement_loop}
        outcome_metrics={@ship_outcome_metrics}
        autonomy_profile={@autonomy_profile}
        outcome_profile={@outcome_profile}
        agent_outcomes={@ship_agent_outcomes}
      />

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Execution brief
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Domain pack</h3>
              <p class="text-sm text-zinc-400">
                {format_domain_pack(brief_value(@brief, "domain_pack"))}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Occupation</h3>
              <p class="text-sm text-zinc-400">{brief_value(@brief, "occupation")}</p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Recommended stack</h3>
              <p class="text-sm text-zinc-400">{brief_value(@brief, "recommended_stack")}</p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Next step</h3>
              <p class="text-sm text-zinc-400">{brief_value(@brief, "next_step")}</p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Acceptance criteria</h3>
              <ul class="space-y-1 text-sm text-zinc-400 list-none p-0 m-0">
                <%= for item <- brief_list(@brief, "acceptance_criteria") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Compiler</h3>
              <p class="text-sm text-zinc-400">
                {brief_value(@compiler, "provider")} / {brief_value(@compiler, "model")}
              </p>
            </div>
          </div>
        </div>

        <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Production boundary
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Risk tier</h3>
              <p class="text-sm text-zinc-400">{boundary_value(@boundary_summary, "risk_tier")}</p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Budget note</h3>
              <p class="text-sm text-zinc-400">
                {boundary_value(@boundary_summary, "budget_note")}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Launch window</h3>
              <p class="text-sm text-zinc-400">
                {boundary_value(@boundary_summary, "launch_window")}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Data summary</h3>
              <p class="text-sm text-zinc-400">
                {boundary_value(@boundary_summary, "data_summary")}
              </p>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Constraints</h3>
              <ul class="space-y-1 text-sm text-zinc-400 list-none p-0 m-0">
                <%= for item <- boundary_list(@boundary_summary, "constraints") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Compliance</h3>
              <ul class="flex flex-wrap gap-1.5 mt-1">
                <%= for item <- boundary_list(@boundary_summary, "compliance") do %>
                  <li>
                    <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2.5 py-1 text-xs text-zinc-300">
                      {item}
                    </span>
                  </li>
                <% end %>
              </ul>
            </div>
            <div>
              <h3 class="text-sm font-semibold text-zinc-300 mb-1">Open questions</h3>
              <ul class="space-y-1 text-sm text-zinc-400 list-none p-0 m-0">
                <%= for item <- boundary_list(@boundary_summary, "open_questions") do %>
                  <li>{item}</li>
                <% end %>
              </ul>
            </div>
          </div>
        </div>

        <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20 lg:col-span-2">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 pb-3 border-b border-white/5">
            Current task context
          </p>
          <%= if @current_task do %>
            <div class="flex items-center justify-between gap-4 mt-4">
              <div class="flex items-center gap-3 min-w-0">
                <span class={[
                  "size-2.5 rounded-full inline-block shrink-0",
                  @current_task.status in ["done", "verified"] && "bg-emerald-400",
                  @current_task.status == "in_progress" && "bg-lime-400",
                  @current_task.status == "queued" && "bg-amber-400",
                  @current_task.status == "paused" && "bg-blue-400",
                  @current_task.status == "blocked" && "bg-red-400"
                ]}>
                </span>
                <strong class="truncate">{@current_task.title}</strong>
              </div>
              <span class={task_status_pill_class(@current_task.status)}>
                {task_status_label(@current_task)}
              </span>
            </div>
            <p class="text-sm text-zinc-400 mt-1">{@current_task.validation_gate}</p>
            <div class="flex flex-wrap items-center gap-x-5 gap-y-2 mt-4 pt-4 border-t border-white/5">
              <button
                id={"current-task-generate-proof-#{@current_task.id}"}
                type="button"
                class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-lime-400/15 text-lime-300 border border-lime-400/30 hover:bg-lime-400/25 hover:text-lime-200 cursor-pointer"
                phx-click="generate_proof"
                phx-value-id={@current_task.id}
              >
                Generate proof
              </button>
              <button
                :if={@current_task.status in ["queued", "in_progress", "blocked"]}
                id={"current-task-pause-#{@current_task.id}"}
                type="button"
                class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.08] hover:text-white cursor-pointer"
                phx-click="pause_task"
                phx-value-id={@current_task.id}
              >
                Pause
              </button>
              <button
                :if={@current_task.status == "paused"}
                id={"current-task-resume-#{@current_task.id}"}
                type="button"
                class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.08] hover:text-white cursor-pointer"
                phx-click="resume_task"
                phx-value-id={@current_task.id}
              >
                Resume
              </button>
              <.link
                :if={Map.get(@latest_proofs, @current_task.id)}
                navigate={~p"/proofs/#{Map.fetch!(@latest_proofs, @current_task.id).id}"}
                class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.08] hover:text-white cursor-pointer"
              >
                View proof
              </.link>
            </div>
            <%= if @current_proof_summary do %>
              <div class="flex flex-wrap gap-2 mt-3">
                <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2.5 py-1 text-xs text-zinc-300">
                  v{@current_proof_summary["version"]}
                </span>
                <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2.5 py-1 text-xs text-zinc-300">
                  risk {@current_proof_summary["risk_score"]}
                </span>
                <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2.5 py-1 text-xs text-zinc-300">
                  {task_verification_label(@current_task, @current_proof_summary)}
                </span>
                <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2.5 py-1 text-xs text-zinc-300">
                  {if @current_proof_summary["deploy_ready"],
                    do: "deploy ready",
                    else: "review required"}
                </span>
              </div>
            <% else %>
              <p :if={done_unverified?(@current_task)} class="text-sm text-zinc-400 mt-1">
                Execution finished, but CK has not verified this task yet. Add checks or regenerate proof.
              </p>
            <% end %>
          <% else %>
            <p class="text-sm text-zinc-400 mt-1">No active task context is available yet.</p>
          <% end %>

          <p class="mt-8 pt-6 border-t border-white/5 text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Task dependencies
          </p>
          <%= if @task_graph.edges == [] do %>
            <p class="text-sm text-zinc-400 mt-1" id="mission-task-deps-empty">
              No dependency edges are recorded yet. When tasks include architecture, feature, and release tracks, edges appear here. The checklist below stays ordered by position.
            </p>
          <% else %>
            <div class="mt-4 space-y-6">
              <ul class="space-y-2 list-none p-0 m-0 mt-2" id="mission-task-edges">
                <%= for edge <- @task_graph.edges do %>
                  <li>
                    {Map.get(@task_title_by_id, edge.from_task_id, "Task #{edge.from_task_id}")}
                    <span class="text-zinc-500"> → </span>
                    {Map.get(@task_title_by_id, edge.to_task_id, "Task #{edge.to_task_id}")}
                    <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2 py-0.5 text-[0.65rem] text-zinc-300 ml-1.5">
                      {edge.dependency_type}
                    </span>
                  </li>
                <% end %>
              </ul>
              <div class="mt-6">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
                  Ready (dependencies satisfied)
                </p>
                <p class="text-sm text-zinc-400 mt-1" id="mission-task-ready">
                  <%= if @task_graph.ready_task_ids == [] do %>
                    No tasks are ready to advance right now.
                  <% else %>
                    {Enum.map_join(@task_graph.ready_task_ids, ", ", fn id ->
                      Map.get(@task_title_by_id, id, "Task #{id}")
                    end)}
                  <% end %>
                </p>
              </div>
            </div>
          <% end %>

          <p class="mt-8 pt-6 border-t border-white/5 text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Task checklist
          </p>
          <ol class="space-y-3 list-none p-0 m-0 mt-3" id="mission-task-checklist">
            <%= for task <- @session.tasks do %>
              <li class="p-4 rounded-2xl border border-white/10 bg-white/[0.03] flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div>
                  <div class="flex items-center gap-2 mb-1">
                    <span class={[
                      "size-2.5 rounded-full inline-block shrink-0",
                      task.status in ["done", "verified"] && "bg-emerald-400",
                      task.status == "in_progress" && "bg-lime-400",
                      task.status == "queued" && "bg-amber-400",
                      task.status == "paused" && "bg-blue-400",
                      task.status == "blocked" && "bg-red-400"
                    ]}>
                    </span>
                    <strong>{task.title}</strong>
                    <span class={task_status_pill_class(task.status)}>
                      {task_status_label(task)}
                    </span>
                  </div>
                  <p class="text-sm text-zinc-400">{task.validation_gate}</p>
                  <%= if task.rollback_boundary do %>
                    <p class="text-xs text-zinc-500 mt-0.5">
                      Rollback: {task.rollback_boundary}
                    </p>
                  <% end %>
                  <%= if task.status == "in_progress" and @active_findings > 0 do %>
                    <p class="text-sm text-amber-500 mt-1">
                      {@active_findings} unresolved finding{if @active_findings != 1, do: "s"} — review before marking done
                    </p>
                  <% end %>
                  <%= for prompt <- task_decision_prompts(task) do %>
                    <p class="text-xs text-zinc-500 mt-0.5">
                      {prompt}
                    </p>
                  <% end %>
                </div>
                <div class="flex flex-col items-start md:items-end gap-1 shrink-0">
                  <%= if task.confidence_score do %>
                    <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2 py-0.5 text-[0.7rem] text-zinc-300">
                      {trunc(task.confidence_score * 100)}% confidence
                    </span>
                  <% end %>
                  <span
                    :if={Map.get(@latest_proofs, task.id)}
                    class="text-xs text-zinc-500"
                  >
                    {task_verification_label(task, Map.get(@latest_proofs, task.id))}
                  </span>
                  <span
                    :if={done_unverified?(task) and is_nil(Map.get(@latest_proofs, task.id))}
                    class="text-xs text-zinc-500"
                  >
                    needs verification evidence
                  </span>
                  <div class="flex flex-wrap items-center justify-start md:justify-end gap-2 mt-1">
                    <%= if Map.get(@latest_proofs, task.id) do %>
                      <.link
                        navigate={~p"/proofs/#{Map.fetch!(@latest_proofs, task.id).id}"}
                        class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.08] hover:text-white cursor-pointer"
                      >
                        View proof
                      </.link>
                    <% end %>
                    <button
                      id={"task-generate-proof-#{task.id}"}
                      type="button"
                      class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-lime-400/15 text-lime-300 border border-lime-400/30 hover:bg-lime-400/25 hover:text-lime-200 cursor-pointer"
                      phx-click="generate_proof"
                      phx-value-id={task.id}
                    >
                      Generate proof
                    </button>
                    <button
                      :if={task.status in ["queued", "in_progress", "blocked"]}
                      id={"task-pause-#{task.id}"}
                      type="button"
                      class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.08] hover:text-white cursor-pointer"
                      phx-click="pause_task"
                      phx-value-id={task.id}
                    >
                      Pause
                    </button>
                    <button
                      :if={task.status == "paused"}
                      id={"task-resume-#{task.id}"}
                      type="button"
                      class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.08] hover:text-white cursor-pointer"
                      phx-click="resume_task"
                      phx-value-id={task.id}
                    >
                      Resume
                    </button>
                  </div>
                </div>
              </li>
            <% end %>
          </ol>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
        <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Workspace context
          </p>
          <div class="flex flex-wrap gap-2 mt-2">
            <span>{workspace_status_label(@current_workspace_context)}</span>
            <span>{get_in(@current_workspace_context, ["git", "branch"]) || "no-branch"}</span>
            <span>
              {String.slice(
                get_in(@current_workspace_context, ["git", "head_sha"]) || "unknown",
                0,
                7
              )}
            </span>
          </div>
          <p class="text-sm text-zinc-400 mt-3">
            {@current_workspace_context["summary_text"]}
          </p>
          <div class="flex flex-wrap gap-2 mt-2">
            <span>
              {length(@current_workspace_context["instruction_files"] || [])} instructions
            </span>
            <span>{length(@current_workspace_context["key_files"] || [])} key files</span>
          </div>
          <details class="mt-4">
            <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 hover:text-lime-200 cursor-pointer select-none">
              View raw workspace JSON
            </summary>
            <pre class="p-4 max-h-96 overflow-auto border border-white/10 rounded-2xl bg-white/[0.03] text-sm text-[#f2e6c9] font-mono whitespace-pre-wrap break-all leading-relaxed mt-4">{Jason.encode!(@current_workspace_context, pretty: true)}</pre>
          </details>
        </div>

        <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
            Relevant memory
          </p>
          <%= if @current_memory_hits == [] do %>
            <p class="text-sm text-zinc-400 mt-3">
              No matching memory has been captured for this task yet.
            </p>
          <% else %>
            <ul class="space-y-3 list-none p-0 m-0 mt-3">
              <%= for hit <- @current_memory_hits do %>
                <li>
                  <strong>{hit.title}</strong>
                  <p class="text-sm text-zinc-400">{hit.summary}</p>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>
      </div>

      <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
        <div class="flex flex-wrap items-center justify-between gap-3 pb-4 border-b border-white/5">
          <p class="text-xs font-semibold uppercase tracking-[0.14em] text-[var(--primary)]">
            Recent transcript
          </p>
          <div class="flex flex-wrap gap-2">
            <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2.5 py-1 text-xs text-zinc-300">
              {@current_transcript_summary["total_events"] || 0} events
            </span>
            <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2.5 py-1 text-xs text-zinc-300">
              {length(@current_recent_events)} recent
            </span>
          </div>
        </div>
        <%= if @current_recent_events == [] do %>
          <p class="text-sm text-zinc-400 mt-4">No transcript events recorded yet.</p>
        <% else %>
          <ul class="space-y-2 list-none p-0 m-0 mt-4">
            <%= for event <- @current_recent_events do %>
              <li class="rounded-2xl border border-white/10 bg-white/[0.03] px-4 py-3 transition hover:bg-white/[0.05]">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <strong class="text-sm text-zinc-100">{event["summary"]}</strong>
                  <span class="inline-flex items-center rounded-full border border-white/10 bg-white/[0.05] px-2 py-0.5 text-[0.65rem] text-zinc-300">
                    {event["event_type"]}
                  </span>
                </div>
                <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-zinc-500">
                  <span class="inline-flex items-center rounded-md border border-white/10 bg-white/[0.04] px-1.5 py-0.5">
                    {event["actor"]}
                  </span>
                  <span class="font-mono tabular-nums tracking-tight">
                    {event_timestamp(event["inserted_at"])}
                  </span>
                </div>
              </li>
            <% end %>
          </ul>
        <% end %>
        <details class="mt-4">
          <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 hover:text-lime-200 cursor-pointer select-none">
            View transcript summary JSON
          </summary>
          <pre class="p-4 max-h-96 overflow-auto border border-white/10 rounded-2xl bg-white/[0.03] text-sm text-[#f2e6c9] font-mono whitespace-pre-wrap break-all leading-relaxed mt-4">{Jason.encode!(@current_transcript_summary, pretty: true)}</pre>
        </details>
      </div>

      <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
          Resume packet
        </p>
        <%= if @current_resume_packet do %>
          <div class="flex flex-wrap gap-2 mt-2">
            <span>{length(@current_resume_packet["unresolved_findings"])} unresolved</span>
            <span>{length(@current_resume_packet["latest_invocations"])} recent runs</span>
            <span>{length(@current_resume_packet["memory_hits"])} memory hits</span>
          </div>
          <details class="mt-4">
            <summary class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 hover:text-lime-200 cursor-pointer select-none">
              View resume packet JSON
            </summary>
            <pre class="p-4 max-h-96 overflow-auto border border-white/10 rounded-2xl bg-white/[0.03] text-sm text-[#f2e6c9] font-mono whitespace-pre-wrap break-all leading-relaxed mt-4">{Jason.encode!(@current_resume_packet, pretty: true)}</pre>
          </details>
        <% else %>
          <p class="text-sm text-zinc-400 mt-3">
            Pause a task to capture a durable resume packet.
          </p>
        <% end %>

        <p class="mt-6 pt-6 border-t border-white/5 text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
          Proxy endpoints
        </p>
        <div class="grid grid-cols-2 gap-3 mt-3">
          <a
            href={@proxy_urls.openai_responses}
            class="block rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm font-semibold text-zinc-300 hover:bg-white/[0.08] hover:text-white transition"
          >
            OpenAI responses
          </a>
          <a
            href={@proxy_urls.openai_chat}
            class="block rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm font-semibold text-zinc-300 hover:bg-white/[0.08] hover:text-white transition"
          >
            OpenAI chat
          </a>
          <a
            href={@proxy_urls.openai_completions}
            class="block rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm font-semibold text-zinc-300 hover:bg-white/[0.08] hover:text-white transition"
          >
            OpenAI completions
          </a>
          <a
            href={@proxy_urls.openai_embeddings}
            class="block rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm font-semibold text-zinc-300 hover:bg-white/[0.08] hover:text-white transition"
          >
            OpenAI embeddings
          </a>
          <a
            href={@proxy_urls.openai_models}
            class="block rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm font-semibold text-zinc-300 hover:bg-white/[0.08] hover:text-white transition"
          >
            OpenAI models
          </a>
          <a
            href={@proxy_urls.openai_realtime}
            class="block rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm font-semibold text-zinc-300 hover:bg-white/[0.08] hover:text-white transition"
          >
            OpenAI realtime
          </a>
          <a
            href={@proxy_urls.anthropic_messages}
            class="block rounded-xl border border-white/10 bg-white/[0.03] px-4 py-3 text-sm font-semibold text-zinc-300 hover:bg-white/[0.08] hover:text-white transition"
          >
            Anthropic messages
          </a>
        </div>
      </div>

      <div class="p-6 rounded-3xl border border-white/10 bg-zinc-900/70 backdrop-blur-xl shadow-2xl shadow-black/20 mt-6">
        <p class="text-xs font-semibold uppercase tracking-[0.14em] text-lime-300 mb-1">
          Findings feed
        </p>
        <%= if @session.findings == [] do %>
          <p class="text-sm text-zinc-400 mt-3">
            No findings yet. ControlKeel is monitoring every agent action.
          </p>
        <% else %>
          <div class="space-y-4 mt-3">
            <%= for finding <- @session.findings do %>
              <article class="p-4 rounded-2xl border border-white/10 bg-white/[0.03] space-y-3">
                <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
                  <h3>{finding.title}</h3>
                  <div class="flex gap-2 items-center">
                    <span class={[
                      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                      finding.severity in ["critical", "high"] &&
                        "bg-red-400/10 text-red-200 ring-red-300/20",
                      finding.severity in ["medium", "moderate"] &&
                        "bg-amber-300/10 text-amber-100 ring-amber-200/20",
                      finding.severity in ["low"] &&
                        "bg-emerald-300/10 text-emerald-100 ring-emerald-200/20",
                      finding.severity not in ["critical", "high", "medium", "moderate", "low"] &&
                        "bg-white/10 text-zinc-300 ring-white/15"
                    ]}>
                      {finding.severity}
                    </span>
                    <span class="inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-white/10 text-zinc-300 ring-white/15">
                      {finding.status}
                    </span>
                  </div>
                </div>
                <p class="text-sm text-zinc-400">{finding.plain_message}</p>
                <p class="text-xs text-zinc-500">
                  {Mission.finding_human_gate_hint(finding)}
                </p>
                <div class="flex justify-between items-center text-xs text-zinc-500 border-t border-white/5 pt-2">
                  <span>{finding.category}</span>
                  <span class="font-mono tabular-nums tracking-tight">
                    {event_timestamp(finding.inserted_at)}
                  </span>
                </div>
                <div class="flex flex-wrap items-center gap-2 border-t border-white/5 pt-2">
                  <button
                    type="button"
                    class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-lime-400/15 text-lime-300 border border-lime-400/30 hover:bg-lime-400/25 hover:text-lime-200 cursor-pointer"
                    phx-click="view_fix"
                    phx-value-id={finding.id}
                  >
                    View fix
                  </button>
                  <%= if finding.status in ["open", "blocked"] do %>
                    <button
                      type="button"
                      class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-emerald-400/15 text-emerald-300 border border-emerald-400/30 hover:bg-emerald-400/25 hover:text-emerald-200 cursor-pointer"
                      phx-click="approve_finding"
                      phx-value-id={finding.id}
                    >
                      Approve
                    </button>
                    <button
                      type="button"
                      class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition bg-red-400/15 text-red-300 border border-red-400/30 hover:bg-red-400/25 hover:text-red-200 cursor-pointer"
                      phx-click="reject_finding"
                      phx-value-id={finding.id}
                    >
                      Reject
                    </button>
                  <% end %>
                  <.link
                    navigate={~p"/findings?#{%{"session_id" => @session.id, "q" => finding.rule_id}}"}
                    class="inline-flex items-center rounded-xl px-3.5 py-2 text-xs font-semibold uppercase tracking-[0.14em] transition border border-white/10 bg-white/[0.03] text-zinc-300 hover:bg-white/[0.08] hover:text-white cursor-pointer"
                  >
                    Open in browser
                  </.link>
                </div>
              </article>
            <% end %>
          </div>
        <% end %>
      </div>

      <FindingComponents.autofix_panel
        :if={@selected_finding && @selected_fix}
        finding={@selected_finding}
        fix={@selected_fix}
        copy_event="copy_fix_prompt"
        close_event="close_fix"
      />
    </section>
    """
  end

  defp safe_assign_session(socket, session) do
    assign_session(socket, session)
  rescue
    e ->
      require Logger
      Logger.warning("MissionControlLive assign_session rescued: #{inspect(e)}")

      socket
      |> assign(:session, session)
      |> assign(:workspace, session.workspace)
      |> assign(:page_title, session.title)
      |> assign(
        :active_findings,
        Enum.count(session.findings || [], &(&1.status in ["open", "blocked"]))
      )
      |> assign(
        :active_tasks,
        Enum.count(session.tasks || [], &(&1.status in ["queued", "in_progress"]))
      )
      |> assign(:task_graph, %{tasks: session.tasks || [], edges: []})
  end

  defp assign_session(socket, session) do
    brief = stringify_keys(session.execution_brief || %{})
    compiler = stringify_keys(Map.get(brief, "compiler", %{}))

    selected_finding =
      case socket.assigns[:selected_finding] do
        %{id: id} -> Enum.find(session.findings, &(&1.id == id))
        _ -> nil
      end

    task_graph = Mission.session_task_graph(session.id)
    task_title_by_id = Map.new(task_graph.tasks, &{&1.id, &1.title})

    {autonomy_profile, outcome_profile, improvement_loop, ship_outcome_metrics,
     ship_agent_outcomes} =
      safe_ship_profile(session)

    assign(socket,
      session: session,
      workspace: session.workspace,
      session_metrics:
        Analytics.session_metrics(session.id) || default_session_metrics(session.id),
      brief: brief,
      boundary_summary: Intent.boundary_summary(brief),
      compiler: compiler,
      current_task: current_task(session.tasks),
      selected_finding: selected_finding,
      selected_fix: maybe_regenerate_fix(selected_finding),
      active_findings: Enum.count(session.findings, &(&1.status in ["open", "blocked"])),
      active_tasks: Enum.count(session.tasks, &(&1.status in ["queued", "in_progress"])),
      compliance_score: compliance_score(session.findings),
      latest_proofs: Mission.latest_proof_bundles_for_session(session.id),
      observability: Observability.session_run(session),
      current_proof_summary: current_task(session.tasks) |> Mission.proof_summary_for_task(),
      current_memory_hits: current_memory_hits(session),
      current_workspace_context: Mission.workspace_context(session),
      current_recent_events: Mission.list_session_events(session.id),
      current_transcript_summary: Mission.transcript_summary(session.id),
      current_resume_packet: current_resume_packet(session),
      task_graph: task_graph,
      task_title_by_id: task_title_by_id,
      agent_label:
        Map.get(Mission.agent_labels(), session.workspace.agent, brief_value(brief, "agent")),
      proxy_urls: Proxy.endpoint_urls(session),
      autonomy_profile: autonomy_profile,
      outcome_profile: outcome_profile,
      improvement_loop: improvement_loop,
      ship_outcome_metrics: ship_outcome_metrics,
      ship_agent_outcomes: ship_agent_outcomes,
      ship_verdict: ship_verdict(improvement_loop, ship_outcome_metrics)
    )
  end

  # Ship-readiness profile is isolated so a raise in the autonomy/outcome
  # computations can never take down the rest of assign_session.
  defp safe_ship_profile(session) do
    {outcome_metrics, agent_outcomes} = Analytics.session_outcome_data(session.id)

    {
      AutonomyLoop.session_autonomy_profile(session),
      AutonomyLoop.session_outcome_profile(session),
      AutonomyLoop.session_improvement_loop(session),
      outcome_metrics,
      agent_outcomes
    }
  rescue
    e ->
      require Logger

      Logger.warning("MissionControlLive ship profile rescued: #{inspect(e)}")

      default_metrics = %{
        proof_backed_task_coverage_percent: nil,
        deploy_ready_task_rate_percent: nil,
        cost_per_deploy_ready_task_cents: nil,
        risky_intervention_rate_percent: nil,
        resume_success_rate_percent: nil,
        average_time_to_first_deploy_ready_proof_seconds: nil
      }

      improvement = %{
        "bottleneck_summary" => %{"primary" => "none", "recommendation" => nil, "signals" => %{}},
        "recommended_next_step" => nil
      }

      {
        %{"label" => "—", "human_role" => nil, "operator_posture" => nil},
        %{"label" => "—", "status" => nil, "target" => nil},
        improvement,
        default_metrics,
        []
      }
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp current_task(tasks) do
    Enum.find(tasks, &(&1.status == "in_progress")) ||
      Enum.find(tasks, &(&1.status == "paused")) ||
      Enum.find(tasks, &(&1.status == "blocked")) ||
      Enum.find(tasks, &(&1.status == "queued"))
  end

  defp current_memory_hits(session) do
    case current_task(session.tasks) do
      nil ->
        []

      task ->
        session
        |> ControlKeel.Memory.retrieve_for_task(task, findings: session.findings, top_k: 5)
        |> Map.get(:entries, [])
    end
  end

  defp current_resume_packet(session) do
    case current_task(session.tasks) do
      nil ->
        nil

      task ->
        case Mission.resume_packet(task.id) do
          {:ok, packet} -> packet
          _error -> nil
        end
    end
  end

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")

  # Ship-readiness verdict, derived from the session's improvement loop signals.
  defp ship_verdict(improvement_loop, _outcome_metrics) do
    bottleneck = get_in(improvement_loop || %{}, ["bottleneck_summary", "primary"]) || "none"
    signals = get_in(improvement_loop || %{}, ["bottleneck_summary", "signals"]) || %{}
    blocked = signals["blocked_findings"] || 0
    deploy_ready = signals["deploy_ready"] == true

    {label, tone} =
      cond do
        blocked > 0 or bottleneck == "unresolved_findings" ->
          {"Blocked", "blocked"}

        bottleneck == "review_wait" ->
          {"Needs review", "review"}

        bottleneck == "missing_deploy_ready_proof" ->
          {"Needs proof evidence", "proof"}

        bottleneck == "budget_pressure" ->
          {"Budget-constrained", "budget"}

        bottleneck == "none" and deploy_ready and blocked == 0 ->
          {"Ready to ship", "ready"}

        true ->
          {"In progress", "progress"}
      end

    %{label: label, tone: tone}
  end

  defp format_duration(nil), do: "Not recorded"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_duration(seconds) when seconds < 3_600, do: "#{Float.round(seconds / 60, 1)}m"
  defp format_duration(seconds), do: "#{Float.round(seconds / 3_600, 1)}h"

  defp workspace_status_label(%{"available" => true}), do: "available"
  defp workspace_status_label(_context), do: "unavailable"

  defp task_status_label(%{status: "verified"}), do: "verified"
  defp task_status_label(%{status: "done"}), do: "done, unverified"

  defp task_status_label(%{status: status}) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp task_status_label(_task), do: "unknown"

  defp task_status_pill_class("verified"),
    do:
      "border border-[var(--border)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp task_status_pill_class("done"),
    do:
      "border border-[var(--border)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp task_status_pill_class(_status),
    do:
      "border border-[var(--border)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp obs_health_pill_class("red"),
    do:
      "border border-[var(--border)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"

  defp obs_health_pill_class("yellow"),
    do:
      "border border-[var(--border)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp obs_health_pill_class(_status),
    do:
      "border border-[var(--border)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp done_unverified?(%{status: "done"}), do: true
  defp done_unverified?(_task), do: false

  defp task_verification_label(_task, %{"verification_status" => "strong"}),
    do: "verification strong"

  defp task_verification_label(_task, %{"verification_status" => "moderate"}),
    do: "verification moderate"

  defp task_verification_label(_task, %{"verification_status" => "weak"}), do: "verification weak"

  defp task_verification_label(_task, %{
         bundle: %{"verification_assessment" => %{"status" => "strong"}}
       }),
       do: "verification strong"

  defp task_verification_label(
         _task,
         %{bundle: %{"verification_assessment" => %{"status" => "moderate"}}}
       ),
       do: "verification moderate"

  defp task_verification_label(_task, %{
         bundle: %{"verification_assessment" => %{"status" => "weak"}}
       }),
       do: "verification weak"

  defp task_verification_label(task, _proof_summary),
    do: if(done_unverified?(task), do: "unverified", else: "verification pending")

  defp task_decision_prompts(task) do
    task
    |> Mission.review_gate_status()
    |> Map.get("decision_prompts", [])
    |> Enum.take(2)
  end

  defp format_currency(cents), do: cents |> Kernel./(100) |> Float.round(2)

  defp brief_value(map, key), do: Map.get(map, key, "Not specified")
  defp brief_list(map, key), do: List.wrap(Map.get(map, key, []))
  defp boundary_value(map, key), do: Map.get(map, key) || "Not specified"

  defp boundary_list(map, key) do
    case Map.get(map, key, []) do
      [] -> ["Not specified"]
      items -> items
    end
  end

  defp format_domain_pack("Not specified"), do: "Not specified"
  defp format_domain_pack(nil), do: "Not specified"
  defp format_domain_pack(domain_pack), do: Intent.pack_label(domain_pack)
  defp maybe_regenerate_fix(nil), do: nil
  defp maybe_regenerate_fix(finding), do: Mission.auto_fix_for_finding(finding)

  defp stringify_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
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

  defp compliance_score([]), do: 100

  defp compliance_score(findings) do
    total = length(findings)
    resolved = Enum.count(findings, &(&1.status in ["approved", "rejected"]))
    round(resolved / total * 100)
  end

  defp donut_color(score) when score >= 80, do: "#22c55e"
  defp donut_color(score) when score >= 50, do: "#f59e0b"
  defp donut_color(_score), do: "#ef4444"

  defp parse_id(value) do
    case Integer.parse(to_string(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_id}
    end
  end

  defp default_session_metrics(session_id) do
    %{
      session_id: session_id,
      funnel_stage: "unknown",
      time_to_first_finding_seconds: nil,
      total_findings: 0,
      blocked_findings_total: 0
    }
  end

  defp session_accessible?(_session, nil), do: true

  defp session_accessible?(%{workspace_id: ws_id}, org_id) when is_integer(org_id) do
    org_id
    |> ControlKeel.Accounts.list_workspaces_for_org()
    |> Enum.any?(fn ws -> ws.id == ws_id end)
  end
end
