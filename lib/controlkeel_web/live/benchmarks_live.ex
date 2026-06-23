defmodule ControlKeelWeb.BenchmarksLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Benchmark
  alias ControlKeel.Intent

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Benchmarks")
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:subjects_dropdown_open, false)
     |> assign(:active_preset, "opencode_compare")
     |> assign(:form, to_form(default_form_params(), as: :benchmark))
     |> assign(:domain_pack_options, domain_pack_options())
     |> refresh_dashboard_assigns()}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case Benchmark.get_run(id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Benchmark run not found.")
         |> push_navigate(to: ~p"/benchmarks")}

      run ->
        {:noreply,
         socket
         |> assign(:run, run)
         |> assign(:matrix, Benchmark.run_matrix(run))
         |> assign(:detail_metrics, Benchmark.run_detail_metrics(run))
         |> assign(:eval_profile, Benchmark.run_eval_profile(run))
         |> assign(:page_title, "Benchmark Run #{run.id}")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:eval_profile, %{})
     |> assign(:page_title, "Benchmarks")
     |> refresh_dashboard_assigns()}
  end

  @impl true
  def handle_event("run", %{"benchmark" => params}, socket) do
    case Benchmark.run_suite(params) do
      {:ok, run} ->
        {:noreply,
         socket
         |> put_flash(:info, "Benchmark run ##{run.id} completed.")
         |> push_navigate(to: ~p"/benchmarks/runs/#{run.id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Benchmark run failed: #{inspect(reason)}")}
    end
  end

  def handle_event("preset_benchmark", %{"preset" => preset}, socket) do
    case benchmark_presets()[preset] do
      nil ->
        {:noreply, socket}

      patch ->
        merged =
          socket.assigns.form.params
          |> Map.merge(patch)

        {:noreply,
         socket
         |> assign(:form, to_form(merged, as: :benchmark))
         |> assign(:active_preset, preset)}
    end
  end

  def handle_event("toggle_subject", %{"id" => id}, socket) do
    current =
      socket.assigns.form.params["subjects"]
      |> List.wrap()
      |> Enum.map(&to_string/1)
      |> Enum.uniq()

    updated =
      if id in current do
        Enum.reject(current, &(&1 == id))
      else
        current ++ [id]
      end
    new_params = Map.put(socket.assigns.form.params, "subjects", updated)

    {:noreply,
     socket
     |> assign(:form, to_form(new_params, as: :benchmark))
     |> assign(:active_preset, nil)}
  end

  def handle_event("toggle_subjects_dropdown", _params, socket) do
    {:noreply, assign(socket, :subjects_dropdown_open, !socket.assigns.subjects_dropdown_open)}
  end

  def handle_event("close_subjects_dropdown", _params, socket) do
    {:noreply, assign(socket, :subjects_dropdown_open, false)}
  end

  def handle_event("benchmark_form_change", %{"benchmark" => params}, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(params, as: :benchmark))
     |> assign(:active_preset, nil)}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="w-[min(1180px,calc(100%-2rem))] mx-auto pt-4 pb-16 max-[900px]:w-[min(calc(100%-1.25rem),1180px)] max-[900px]:pt-6">
        <.link
          navigate={~p"/benchmarks"}
          class="inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.14em] text-neutral-400 hover:text-neutral-200"
        >
          <.icon name="hero-arrow-left" class="w-3 h-3" /> Back to benchmarks
        </.link>

        <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
          <div class="space-y-1">
            <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
              Run ##{@run.id} — {@run.suite.name}
            </h2>
          </div>

          <a
            href={~p"/api/v1/benchmarks/runs/#{@run.id}/export?format=csv"}
            class="inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.14em] border border-neutral-400 rounded-xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] px-3 py-2 text-neutral-400 hover:text-neutral-200 hover:border-neutral-400"
          >
            <.icon name="hero-document-text" class="w-3 h-3" /> Export CSV
          </a>
        </div>

        <div class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold mb-4">
            Performance metrics
          </p>

          <div class="grid gap-4 grid-cols-2 max-[900px]:grid-cols-1">
            <div>
              <h3>Catch rate</h3>
              <p class="text-[var(--ck-muted)]">{@run.catch_rate}%</p>
            </div>

            <div>
              <h3>Block rate</h3>
              <p class="text-[var(--ck-muted)]">{@detail_metrics.block_rate}%</p>
            </div>

            <div>
              <h3>Expected rule hit rate</h3>
              <p class="text-[var(--ck-muted)]">{@detail_metrics.expected_rule_hit_rate}%</p>
            </div>

            <div>
              <h3>Average overhead</h3>
              <p class="text-[var(--ck-muted)]">{format_percent(@run.average_overhead_percent)}</p>
            </div>
          </div>

          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold mt-8 mb-4">
            Run metadata
          </p>
          <div class="grid gap-4 grid-cols-2 max-[900px]:grid-cols-1">
            <div>
              <h3>Status</h3>
              <p class="text-[var(--ck-muted)]">{run_status_label(@run.status)}</p>
            </div>
            <div>
              <h3>Baseline subject</h3>
              <p class="text-[var(--ck-muted)]">
                {subject_label_by_id(@subjects_by_id, @run.baseline_subject)}
              </p>
            </div>
            <div>
              <h3>Subjects</h3>
              <p class="text-[var(--ck-muted)]">
                {Enum.map_join(@run.subjects, ", ", &subject_label_by_id(@subjects_by_id, &1))}
              </p>
            </div>
            <div>
              <h3>Median latency</h3>
              <p class="text-[var(--ck-muted)]">{format_latency(@run.median_latency_ms)}</p>
            </div>
            <div>
              <h3>Domain packs</h3>
              <p class="text-[var(--ck-muted)]">
                {Enum.map_join(Benchmark.domain_packs_for_run(@run), ", ", &format_domain_pack/1)}
              </p>
            </div>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] my-6 rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Promotion integrity
          </p>
          <% integrity = get_in(@eval_profile, ["promotion_integrity"]) || %{} %>
          <div class="flex items-center justify-between gap-4 max-[900px]:flex-col max-[900px]:items-start">
            <h3>{integrity["status"] || "unknown"}</h3>
            <span class="border border-[var(--ck-stroke)] rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
              {Enum.join(integrity["evidence_channels"] || [], ", ")}
            </span>
          </div>
          <p class="text-[var(--ck-muted)]">
            <%= case integrity["warnings"] || [] do %>
              <% [] -> %>
                Held-out, diversity, and classification evidence are present for this run.
              <% warnings -> %>
                Warnings: {Enum.join(warnings, ", ")}
            <% end %>
          </p>
        </div>

        <div class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
          <div class="flex items-center justify-between gap-4">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Scenario matrix
            </p>
            <span class="text-xs text-[var(--ck-muted)]">
              {length(@matrix.scenarios)} {if length(@matrix.scenarios) == 1,
                do: "scenario",
                else: "scenarios"}
            </span>
          </div>

          <%= if @matrix.scenarios == [] do %>
            <div class="mt-4 rounded-[1rem] border border-dashed border-[var(--ck-stroke)] p-8 text-center">
              <p class="text-[var(--ck-text)] text-sm font-medium">No scenarios recorded</p>
              <p class="text-[var(--ck-muted)] text-sm mt-1">This run has no scenario results yet.</p>
            </div>
          <% else %>
            <div class="grid gap-4 mt-4 grid-cols-2 max-[900px]:grid-cols-1">
              <%= for row <- @matrix.scenarios do %>
                <article
                  id={"scenario-#{row.scenario.slug}"}
                  class="border border-white/[0.07] rounded-[1.1rem] bg-white/[0.03] p-4 grid gap-3"
                >
                  <div class="flex items-start justify-between gap-3">
                    <div class="min-w-0 space-y-1">
                      <strong class="block leading-snug">{row.scenario.name}</strong>
                      <p class="text-[var(--ck-muted)] text-sm">{row.scenario.incident_label}</p>
                    </div>
                    <div class="flex flex-col items-end gap-1 shrink-0">
                      <span class="border border-[var(--ck-stroke)] bg-white/5 rounded-full px-2 py-0.5 text-[0.7rem]">
                        {format_domain_pack(get_in(row.scenario.metadata || %{}, ["domain_pack"]))}
                      </span>
                      <span class="text-[0.7rem] text-[var(--ck-muted)] uppercase tracking-wider">
                        {get_in(row.scenario.metadata || %{}, ["risk_tier"]) || "n/a"}
                      </span>
                    </div>
                  </div>

                  <div class="grid gap-2">
                    <%= for {result, subject_id} <- Enum.zip(row.results, @matrix.subjects) do %>
                      <.scenario_result
                        result={result}
                        subject_label={subject_label_by_id(@subjects_by_id, subject_id)}
                      />
                    <% end %>
                  </div>
                </article>
              <% end %>
            </div>
          <% end %>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="w-[min(1180px,calc(100%-2rem))] mx-auto pt-8 pb-16 max-[900px]:w-[min(calc(100%-1.25rem),1180px)] max-[900px]:pt-6">
        <div class="space-y-1">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Benchmark engine
          </h2>
          <p class="text-[var(--ck-muted)]">
            Compare governed subjects and external agents on the same scenario suites, then keep the results as product evidence.
          </p>
        </div>

        <div class="grid gap-4 grid-cols-[2fr_1fr] mt-6">
          <div class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 grid gap-4">
            <div class="flex flex-col gap-3 mb-6">
              <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
                Quick presets
              </p>
              <p class="text-[var(--ck-muted)] text-sm mb-2 max-w-[42rem] leading-relaxed">
                One-click subject and suite configurations. Pick one to populate the form below.
              </p>

              <div class="flex flex-wrap gap-2">
                <button
                  :for={{preset_id, preset_value, preset_label} <- preset_chips()}
                  type="button"
                  id={preset_id}
                  phx-click="preset_benchmark"
                  phx-value-preset={preset_value}
                  aria-pressed={to_string(preset_value == @active_preset)}
                  class={[
                    "group inline-flex items-center gap-2 rounded-full border px-4 py-2 text-sm transition-all duration-150 active:scale-[0.98]",
                    if(preset_value == @active_preset,
                      do: "border-[var(--ck-lime)] bg-[rgba(196,240,66,0.16)] text-[var(--ck-lime)]",
                      else:
                        "border-[var(--ck-stroke)] bg-white/5 text-[var(--ck-text)] hover:-translate-y-px hover:border-[var(--ck-lime)] hover:bg-[rgba(196,240,66,0.08)] hover:text-[var(--ck-lime)]"
                    )
                  ]}
                >
                  {preset_label}
                </button>
              </div>
            </div>
            <.form
              for={@form}
              id="benchmark-runner"
              phx-submit="run"
              phx-change="benchmark_form_change"
            >
              <div class="flex flex-col gap-4">
                <.input
                  field={@form[:suite]}
                  type="select"
                  label="Suite"
                  options={Enum.map(@suites, &{"#{&1.name} (#{&1.slug})", &1.slug})}
                />
                <.subject_multi_select
                  field={@form[:subjects]}
                  label="Subjects"
                  options={subject_options(@available_subjects)}
                  selected={@form[:subjects].value}
                  open={@subjects_dropdown_open}
                  id="benchmark-subjects-input"
                />
                <.input
                  field={@form[:baseline_subject]}
                  type="select"
                  label="Baseline subject"
                  options={subject_options(@available_subjects)}
                  id="benchmark-baseline-input"
                />
                <.input
                  field={@form[:domain_pack]}
                  type="select"
                  label="Run only this domain"
                  prompt="All suite scenarios"
                  options={@domain_pack_options}
                />
              </div>
              <div class="flex items-center justify-between gap-4 mt-4 max-[900px]:flex-col max-[900px]:items-start">
                <button
                  type="submit"
                  class="inline-flex items-center justify-center gap-[0.4rem] px-4 py-2 rounded-full bg-[var(--ck-lime)] text-[#11170d] font-bold transition-transform transition-shadow duration-150 hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)]"
                >
                  Run benchmark
                </button>
              </div>
            </.form>
            <p class="text-[var(--ck-muted)] text-sm mt-4">
              For a reproducible external comparison, start with `controlkeel_validate,opencode_manual`
              and import the OpenCode output after the awaiting-import run finishes.
            </p>
          </div>

          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 h-fit">
            <div class="space-y-2 border-b border-[var(--ck-stroke)] pb-4 mb-4">
              <p>
                Suites: <span class="text-[var(--ck-lime)]">{@summary.total_suites}</span>
              </p>

              <p>
                Runs: <span class="text-[var(--ck-lime)]">{@summary.total_runs}</span>
              </p>

              <p>
                Average catch rate:
                <span class="text-[var(--ck-lime)]">
                  {format_percent(@summary.average_catch_rate)}
                </span>
              </p>

              <p>
                Average overhead:
                <span class="text-[var(--ck-lime)]">
                  {format_percent(@summary.average_overhead_percent)}
                </span>
              </p>
            </div>

            <p class="uppercase tracking-[0.14em] text-[var(--ck-lime)] font-semibold mt-4">
              Blessed external path
            </p>
            <h3 class="my-2">OpenCode vs ControlKeel</h3>
            <p class="text-[var(--ck-muted)] text-sm">
              The recommended first external comparison path is OpenCode. Start with a manual import
              subject for the quickest reproducible run, then swap to a shell-based wrapper if you
              want fully scripted replay.
            </p>
            <ul class="grid gap-2 mt-4 list-none text-sm">
              <li>
                Create or review `controlkeel/benchmark_subjects.json` with the OpenCode subject you want to import.
              </li>
              <li>
                Run the suite once with `opencode_manual` to create awaiting-import records.
              </li>
              <li>
                Import captured OpenCode output or replace the subject with a scripted shell command later.
              </li>
            </ul>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
          <div class="flex items-center justify-between gap-4">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recent runs
            </p>
            <span :if={@recent_runs != []} class="text-xs text-[var(--ck-muted)]">
              {length(@recent_runs)} {if length(@recent_runs) == 1, do: "run", else: "runs"}
            </span>
          </div>
          <%= if @recent_runs == [] do %>
            <div class="mt-4 rounded-[1rem] border border-dashed border-[var(--ck-stroke)] p-8 text-center">
              <p class="text-[var(--ck-text)] text-sm font-medium">
                No benchmark runs yet
              </p>
              <p class="text-[var(--ck-muted)] text-sm mt-1">
                Pick a preset above and run your first suite to see results here.
              </p>
            </div>
          <% else %>
            <div class="overflow-x-auto mt-4">
              <table id="benchmark-runs" class="min-w-full text-sm">
                <thead>
                  <tr class="text-left text-xs text-[var(--ck-muted)] uppercase tracking-wider">
                    <th class="py-2 pr-4">Run</th>
                    <th class="py-2 pr-4">Suite</th>
                    <th class="py-2 pr-4">Status</th>
                    <th class="py-2 pr-4">Catch rate</th>
                    <th class="py-2 pr-4">Baseline</th>
                    <th class="py-2 pr-4">Domains</th>
                    <th class="py-2 pr-4 text-right">Overhead</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-[var(--ck-stroke)]">
                  <%= for run <- @recent_runs do %>
                    <tr id={"run-#{run.id}"} class="align-top">
                      <td class="py-3 pr-4">
                        <.link
                          navigate={~p"/benchmarks/runs/#{run.id}"}
                          class="font-semibold text-[var(--ck-lime)]"
                        >
                          ##{run.id}
                        </.link>
                      </td>
                      <td class="py-3 pr-4 text-[var(--ck-muted)] truncate">
                        {run.suite.name || run.suite.slug}
                      </td>
                      <td class="py-3 pr-4">
                        <span class="inline-flex items-center rounded-full px-3 py-1 text-xs bg-white/5 border border-[var(--ck-stroke)]">
                          {run_status_label(run.status)}
                        </span>
                      </td>
                      <td class="py-3 pr-4"><strong>{format_percent(run.catch_rate)}</strong></td>
                      <td class="py-3 pr-4 text-[var(--ck-muted)]">
                        {subject_label_by_id(@subjects_by_id, run.baseline_subject)}
                      </td>
                      <td class="py-3 pr-4">
                        <div class="flex flex-wrap gap-2">
                          <%= for pack <- Benchmark.domain_packs_for_run(run) do %>
                            <span class="border border-[var(--ck-stroke)] bg-white/5 rounded-full px-2 py-0.5 text-[0.75rem]">
                              {format_domain_pack(pack)}
                            </span>
                          <% end %>
                        </div>
                      </td>
                      <td class="py-3 pr-4 text-right text-[var(--ck-muted)]">
                        {format_percent(run.average_overhead_percent)}
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>

        <div class="border border-[var(--ck-stroke)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-6">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Built-in suites
          </p>
          <p class="text-[var(--ck-muted)] text-xs mt-1">
            Built-ins are always present. External subjects appear when the current project has a
            `controlkeel/benchmark_subjects.json` file.
          </p>

          <div class="grid gap-4 m-0 p-0 list-none mt-4 max-h-[28rem] overflow-y-auto pr-1">
            <%= for suite <- @suites do %>
              <article
                class="border border-white/[0.07] rounded-[1.1rem] p-4 bg-white/[0.03] grid gap-[0.55rem]"
                id={"suite-#{suite.slug}"}
              >
                <div class="flex items-center justify-between gap-4 max-[900px]:flex-col max-[900px]:items-start">
                  <h3>{suite.name}</h3>
                  <span class="border border-[var(--ck-stroke)] rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
                    v{suite.version}
                  </span>
                </div>
                <p class="text-[var(--ck-muted)]">{suite.description}</p>
                <div class="flex items-center justify-between gap-4">
                  <span>{length(suite.scenarios)} scenarios</span>
                  <span>{suite.status}</span>
                </div>
                <div class="flex flex-wrap gap-2 mt-2">
                  <%= for pack <- Benchmark.domain_packs_for_suite(suite) do %>
                    <span class="border border-[var(--ck-stroke)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem]">
                      {format_domain_pack(pack)}
                    </span>
                  <% end %>
                </div>
              </article>
            <% end %>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp default_form_params do
    %{
      "suite" => "vibe_failures_v1",
      "subjects" => ["controlkeel_validate", "opencode_manual"],
      "baseline_subject" => "controlkeel_validate",
      "domain_pack" => ""
    }
  end

  defp preset_chips do
    [
      {"benchmark-preset-opencode", "opencode_compare", "OpenCode comparison"},
      {"benchmark-preset-ck-only", "ck_only", "ControlKeel validate only"},
      {"benchmark-preset-proxy", "ck_proxy", "Validate + governed proxy"},
      {"benchmark-preset-copilot-vs-opencode", "copilot_vs_opencode", "Copilot vs OpenCode"},
      {"benchmark-preset-full-compare", "full_compare", "Full host comparison"}
    ]
  end

  defp benchmark_presets do
    %{
      "opencode_compare" => %{
        "subjects" => ["controlkeel_validate", "opencode_manual"],
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_only" => %{
        "subjects" => ["controlkeel_validate"],
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_proxy" => %{
        "subjects" => ["controlkeel_validate", "controlkeel_proxy"],
        "baseline_subject" => "controlkeel_validate"
      },
      "copilot_vs_opencode" => %{
        "suite" => "host_comparison_v1",
        "subjects" => ["controlkeel_validate", "opencode_manual", "copilot_manual"],
        "baseline_subject" => "controlkeel_validate"
      },
      "full_compare" => %{
        "suite" => "host_comparison_v1",
        "subjects" => [
          "controlkeel_validate",
          "opencode_manual",
          "copilot_manual",
          "gemini_manual",
          "codex_manual",
          "claude_manual"
        ],
        "baseline_subject" => "controlkeel_validate"
      }
    }
  end

  defp refresh_dashboard_assigns(socket) do
    subjects = Benchmark.available_subjects()

    socket
    |> assign(:summary, Benchmark.benchmark_summary([]))
    |> assign(:suites, Benchmark.list_suites([]))
    |> assign(:recent_runs, Benchmark.list_recent_runs([]))
    |> assign(:available_subjects, subjects)
    |> assign(:subjects_by_id, Map.new(subjects, fn s -> {s["id"], s} end))
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

  defp decision_badge_class(nil),
    do: "border-[var(--ck-stroke)] bg-white/5 text-[var(--ck-muted)]"

  defp decision_badge_class("block"),
    do: "border-[rgba(255,143,107,0.35)] bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"

  defp decision_badge_class("warn"),
    do: "border-[rgba(255,207,107,0.35)] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp decision_badge_class("allow"),
    do: "border-[rgba(125,226,174,0.35)] bg-[rgba(125,226,174,0.12)] text-[#d2ffe7]"

  defp decision_badge_class(_), do: "border-[var(--ck-stroke)] bg-white/5 text-[var(--ck-muted)]"

  defp decision_label(nil), do: "no ruling"
  defp decision_label("block"), do: "blocked"
  defp decision_label("warn"), do: "warned"
  defp decision_label("allow"), do: "allowed"
  defp decision_label(other), do: other

  defp status_label(nil), do: "unknown"
  defp status_label("completed"), do: "completed"
  defp status_label("failed"), do: "failed"
  defp status_label("timed_out"), do: "timed out"
  defp status_label("awaiting_import"), do: "awaiting import"
  defp status_label("pending"), do: "pending"
  defp status_label(other), do: String.replace(other, "_", " ")

  defp status_badge_class(status) when status in ["failed", "timed_out"] do
    "border-[rgba(255,143,107,0.35)] bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  end

  defp status_badge_class(status) when status in ["awaiting_import", "pending"] do
    "border-[rgba(255,207,107,0.35)] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  end

  defp status_badge_class(_), do: "border-[var(--ck-stroke)] bg-white/5 text-[var(--ck-muted)]"

  defp subject_options(subjects) do
    Enum.map(subjects, fn subject ->
      {subject_label(subject), subject["id"]}
    end)
  end

  defp scenario_result(assigns) do
    ~H"""
    <div class="rounded-[0.8rem] bg-white/[0.02] px-3 py-2.5 grid gap-2">
      <%= if @result do %>
        <div class="flex items-center justify-between gap-2">
          <div class="flex items-center gap-1.5 min-w-0">
            <span class="text-sm font-semibold truncate">{@subject_label}</span>
            <%= if @result.matched_expected do %>
              <.icon name="hero-check-badge" class="w-4 h-4 text-[var(--ck-lime)] shrink-0" />
            <% end %>
          </div>
          <div class="flex flex-wrap gap-1.5 justify-end shrink-0">
            <span class={[
              "rounded-full px-2 py-0.5 text-[0.7rem] font-medium border",
              decision_badge_class(@result.decision)
            ]}>
              {decision_label(@result.decision)}
            </span>
            <span
              :if={status_label(@result.status)}
              class={[
                "rounded-full px-2 py-0.5 text-[0.7rem] border",
                status_badge_class(@result.status)
              ]}
            >
              {status_label(@result.status)}
            </span>
          </div>
        </div>
        <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-[var(--ck-muted)]">
          <span>{@result.findings_count} findings</span>
          <span>latency {format_latency(@result.latency_ms)}</span>
          <span>overhead {format_percent(@result.overhead_percent)}</span>
        </div>
      <% else %>
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm text-[var(--ck-muted)] truncate">{@subject_label}</span>
          <span class="text-[0.7rem] text-[var(--ck-muted)] uppercase tracking-wider">
            no result
          </span>
        </div>
      <% end %>
    </div>
    """
  end

  defp subject_multi_select(assigns) do
    assigns =
      assigns
      |> assign(:selected, List.wrap(assigns[:selected]))
      |> assign(
        :labels_by_value,
        Map.new(assigns[:options] || [], fn {label, value} -> {value, label} end)
      )
      |> assign_new(:open, fn -> false end)

    ~H"""
    <div
      class="fieldset mb-2 relative"
      id={@id}
      phx-click-away={@open && "close_subjects_dropdown"}
    >
      <span :if={@label} class="label mb-1 block">{@label}</span>
      <div :if={@selected != []} class="flex flex-wrap gap-2 mb-2">
        <span
          :for={selected_value <- @selected}
          class="inline-flex items-center gap-1 rounded-full border border-[var(--ck-stroke)] text-[var(--ck-muted)] pl-3 pr-1.5 py-1 text-xs"
        >
          {Map.get(@labels_by_value, selected_value, selected_value)}
          <button
            type="button"
            phx-click="toggle_subject"
            phx-value-id={selected_value}
            aria-label={"Remove #{Map.get(@labels_by_value, selected_value, selected_value)}"}
            class="inline-flex items-center justify-center rounded-full p-0.5 hover:text-[var(--ck-lime)] transition-colors"
          >
            <.icon name="hero-x-mark" class="w-3 h-3" />
          </button>
        </span>
      </div>
      <button
        type="button"
        phx-click="toggle_subjects_dropdown"
        aria-haspopup="listbox"
        aria-expanded={to_string(@open)}
        class={[
          "select w-full flex items-center justify-between gap-2 px-3 py-2 text-left",
          "focus:outline-none focus:border-[var(--ck-lime)]"
        ]}
      >
        <span class="text-[var(--ck-muted)]">Select subjects</span>
        <.icon
          name="hero-chevron-down"
          class={["w-4 h-4 shrink-0 transition-transform", @open && "rotate-180"]}
        />
      </button>
      <div
        :if={@open}
        class="absolute z-30 mt-1 w-full max-h-72 overflow-y-auto rounded-[1rem] border border-[var(--ck-stroke)] bg-[#0d1216] shadow-[0_24px_80px_rgba(0,0,0,0.45)] p-1"
        role="listbox"
        aria-label={@label}
        aria-multiselectable="true"
      >
        <button
          :for={{option_label, option_value} <- @options}
          type="button"
          role="option"
          aria-selected={if(option_value in @selected, do: "true", else: "false")}
          data-subject-id={option_value}
          phx-click="toggle_subject"
          phx-value-id={option_value}
          class={[
            "w-full flex items-center gap-2 px-3 py-2 rounded-[0.6rem] text-left text-sm transition-colors cursor-pointer",
            if(option_value in @selected,
              do: "bg-[rgba(196,240,66,0.14)] text-[#d2ffe7]",
              else: "text-[var(--ck-text)] hover:bg-white/5"
            )
          ]}
        >
          <.icon
            name="hero-check"
            class={[
              "w-4 h-4 shrink-0",
              if(option_value in @selected, do: "text-[var(--ck-lime)]", else: "opacity-0")
            ]}
          />
          <span class="truncate">{option_label}</span>
        </button>
      </div>
      <input
        :for={selected_value <- @selected}
        type="hidden"
        name={"#{@field.name}[]"}
        value={selected_value}
      />
    </div>
    """
  end

  defp subject_label_by_id(subjects_by_id, id) do
    subject_label(Map.get(subjects_by_id, id) || %{"id" => id})
  end

  defp subject_label(subject) do
    label = subject["label"] || subject["id"] || "Unknown subject"

    suffix =
      cond do
        subject["configured"] == false -> " (needs config)"
        subject["type"] in ["manual_import", "shell"] -> " (external)"
        true -> ""
      end

    label <> suffix
  end

  defp format_latency(nil), do: "n/a"
  defp format_latency(value), do: "#{value}ms"

  defp domain_pack_options do
    Enum.map(Intent.supported_packs(), &{Intent.pack_label(&1), &1})
  end

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(domain_pack), do: Intent.pack_label(domain_pack)

  defp run_status_label(nil), do: "unknown"

  defp run_status_label(status) when is_binary(status) do
    status
    |> String.replace("_", " ")
    |> String.trim()
    |> String.capitalize()
  end
end
