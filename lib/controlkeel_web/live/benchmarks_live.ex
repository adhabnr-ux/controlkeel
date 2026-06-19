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
     |> assign(:form, to_form(default_form_params(), as: :benchmark))
     |> assign(:filter_form, to_form(%{"domain_pack" => ""}, as: :filters))
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
         |> assign(:page_title, "Benchmark Run #{run.id}")}
    end
  end

  def handle_params(%{"domain_pack" => domain_pack} = _params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:page_title, "Benchmarks")
     |> assign(:filter_form, to_form(%{"domain_pack" => domain_pack}, as: :filters))
     |> refresh_dashboard_assigns(domain_pack)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:run, nil)
     |> assign(:matrix, %{subjects: [], scenarios: []})
     |> assign(:detail_metrics, %{})
     |> assign(:page_title, "Benchmarks")
     |> assign(:filter_form, to_form(%{"domain_pack" => ""}, as: :filters))
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

  def handle_event("filter_domain", %{"filters" => filters}, socket) do
    {:noreply, push_patch(socket, to: ~p"/benchmarks?#{domain_filter_params(filters)}")}
  end

  def handle_event("preset_benchmark", %{"preset" => preset}, socket) do
    case benchmark_presets()[preset] do
      nil ->
        {:noreply, socket}

      patch ->
        merged =
          socket.assigns.form.params
          |> Map.merge(patch)

        {:noreply, assign(socket, :form, to_form(merged, as: :benchmark))}
    end
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="w-[min(1180px,calc(100%-2rem))] mx-auto pt-8 pb-16 max-[900px]:w-[min(calc(100%-1.25rem),1180px)] max-[900px]:pt-6">
        <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
          <div>
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Benchmark run
            </p>
            <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">
              Run ##{@run.id} — {@run.suite.name}
            </h1>
            <p class="text-[var(--ck-muted)] max-w-[48rem] text-[1.05rem] leading-[1.7]">
              Compare governed and external subjects across the same failure scenarios without polluting mission data.
            </p>
          </div>
          <div class="flex items-center justify-between gap-4 max-[900px]:flex-col max-[900px]:items-start">
            <.link
              navigate={~p"/benchmarks"}
              class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
            >
              Back to benchmarks
            </.link>
            <a
              href={~p"/api/v1/benchmarks/runs/#{@run.id}/export?format=csv"}
              class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
            >
              Export CSV
            </a>
          </div>
        </div>

        <div class="grid gap-4 grid-cols-[repeat(auto-fit,minmax(180px,1fr))] mt-5">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Catch rate
            </p>
            <strong>{@run.catch_rate}%</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Block rate
            </p>
            <strong>{@detail_metrics.block_rate}%</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Expected rule hit rate
            </p>
            <strong>{@detail_metrics.expected_rule_hit_rate}%</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Average overhead
            </p>
            <strong>{format_percent(@run.average_overhead_percent)}</strong>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Run metadata
          </p>
          <div class="grid gap-4 grid-cols-2 max-[900px]:grid-cols-1">
            <div>
              <h3>Status</h3>
              <p class="text-[var(--ck-muted)]">{@run.status}</p>
            </div>
            <div>
              <h3>Baseline subject</h3>
              <p class="text-[var(--ck-muted)]">{@run.baseline_subject}</p>
            </div>
            <div>
              <h3>Subjects</h3>
              <p class="text-[var(--ck-muted)]">{Enum.join(@run.subjects, ", ")}</p>
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

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Promotion integrity
          </p>
          <% integrity = get_in(Benchmark.run_eval_profile(@run), ["promotion_integrity"]) || %{} %>
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

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
            Scenario matrix
          </p>
          <div class="overflow-x-auto">
            <table class="min-w-full w-full text-sm" id="benchmark-matrix">
              <thead>
                <tr>
                  <th class="text-left py-2 pr-4">Scenario</th>
                  <%= for subject <- @matrix.subjects do %>
                    <th class="text-left py-2 pr-4">{subject}</th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @matrix.scenarios do %>
                  <tr id={"scenario-#{row.scenario.slug}"}>
                    <td class="align-top py-3 pr-4">
                      <strong>{row.scenario.name}</strong>
                      <p class="text-[var(--ck-muted)]">{row.scenario.incident_label}</p>
                      <p class="text-[var(--ck-muted)]">
                        {format_domain_pack(get_in(row.scenario.metadata || %{}, ["domain_pack"]))} • {get_in(
                          row.scenario.metadata || %{},
                          ["risk_tier"]
                        ) || "n/a"}
                      </p>
                    </td>
                    <%= for result <- row.results do %>
                      <td class="align-top py-3 pr-4">
                        <%= if result do %>
                          <div class="flex flex-wrap gap-2">
                            <span class="border border-[var(--ck-stroke)] rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
                              {result.status}
                            </span>
                            <span
                              :if={result.decision}
                              class="border border-[var(--ck-stroke)] rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
                            >
                              {result.decision}
                            </span>
                          </div>
                          <p class="text-[var(--ck-muted)]">{result.findings_count} findings</p>
                          <p class="text-[var(--ck-muted)]">
                            latency {format_latency(result.latency_ms)}
                          </p>
                          <p class="text-[var(--ck-muted)]">
                            overhead {format_percent(result.overhead_percent)}
                          </p>
                        <% else %>
                          <p class="text-[var(--ck-muted)]">No result</p>
                        <% end %>
                      </td>
                    <% end %>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="w-[min(1180px,calc(100%-2rem))] mx-auto pt-8 pb-16 max-[900px]:w-[min(calc(100%-1.25rem),1180px)] max-[900px]:pt-6">
        <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
          <div>
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Benchmark engine
            </p>
            <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">
              Run persisted benchmark matrices
            </h1>
            <p class="text-[var(--ck-muted)] max-w-[48rem] text-[1.05rem] leading-[1.7]">
              Compare governed subjects and external agents on the same scenario suites, then keep the results as product evidence.
            </p>
          </div>
          <.link
            navigate={~p"/"}
            class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
          >
            Back home
          </.link>
        </div>

        <div class="grid gap-4 grid-cols-[repeat(auto-fit,minmax(180px,1fr))] mt-5">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Suites
            </p>
            <strong>{@summary.total_suites}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Runs
            </p>
            <strong>{@summary.total_runs}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Average catch rate
            </p>
            <strong>{format_percent(@summary.average_catch_rate)}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Average overhead
            </p>
            <strong>{format_percent(@summary.average_overhead_percent)}</strong>
          </div>
        </div>

        <div class="grid grid-cols-[minmax(0,1.35fr)_minmax(280px,0.75fr)] gap-6 max-[900px]:grid-cols-1 mt-6">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Blessed external path
            </p>
            <h3 class="mb-2">OpenCode vs ControlKeel</h3>
            <p class="text-[var(--ck-muted)]">
              The recommended first external comparison path is OpenCode. Start with a manual import
              subject for the quickest reproducible run, then swap to a shell-based wrapper if you
              want fully scripted replay.
            </p>
            <ul class="grid gap-4 m-0 mt-3 p-0 list-none">
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
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Available subjects
            </p>
            <div class="flex flex-wrap gap-2">
              <%= for subject <- @available_subjects do %>
                <span class="border border-[var(--ck-stroke)] bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem]">
                  {subject_label(subject)}
                </span>
              <% end %>
            </div>
            <p class="text-[var(--ck-muted)] mt-3">
              Built-ins are always present. External subjects appear when the current project has a
              `controlkeel/benchmark_subjects.json` file.
            </p>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 grid gap-4 mt-6">
          <.form for={@filter_form} id="benchmark-filters" phx-change="filter_domain">
            <div class="grid grid-cols-5 gap-4 max-[900px]:grid-cols-1">
              <.input
                field={@filter_form[:domain_pack]}
                type="select"
                label="Domain pack"
                prompt="All domains"
                options={@domain_pack_options}
              />
            </div>
          </.form>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 grid gap-4">
          <datalist id="benchmark-subject-suggestions">
            <%= for subject <- @available_subjects do %>
              <option value={subject["id"]}>{subject["label"] || subject["id"]}</option>
            <% end %>
          </datalist>
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold mb-2">
            Quick presets
          </p>
          <div class="flex items-center justify-between gap-2 mb-4 flex-wrap max-[900px]:flex-col max-[900px]:items-start">
            <button
              type="button"
              class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
              id="benchmark-preset-opencode"
              phx-click="preset_benchmark"
              phx-value-preset="opencode_compare"
            >
              OpenCode comparison
            </button>
            <button
              type="button"
              class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
              id="benchmark-preset-ck-only"
              phx-click="preset_benchmark"
              phx-value-preset="ck_only"
            >
              ControlKeel validate only
            </button>
            <button
              type="button"
              class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
              id="benchmark-preset-proxy"
              phx-click="preset_benchmark"
              phx-value-preset="ck_proxy"
            >
              Validate + governed proxy
            </button>
            <button
              type="button"
              class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
              id="benchmark-preset-copilot-vs-opencode"
              phx-click="preset_benchmark"
              phx-value-preset="copilot_vs_opencode"
            >
              Copilot vs OpenCode
            </button>
            <button
              type="button"
              class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
              id="benchmark-preset-full-compare"
              phx-click="preset_benchmark"
              phx-value-preset="full_compare"
            >
              Full host comparison
            </button>
          </div>
          <.form for={@form} id="benchmark-runner" phx-submit="run">
            <div class="grid grid-cols-5 gap-4 max-[900px]:grid-cols-1">
              <.input
                field={@form[:suite]}
                type="select"
                label="Suite"
                options={Enum.map(@suites, &{"#{&1.name} (#{&1.slug})", &1.slug})}
              />
              <.input
                field={@form[:subjects]}
                type="text"
                label="Subjects (comma-separated)"
                placeholder="controlkeel_validate,opencode_manual"
                list="benchmark-subject-suggestions"
                id="benchmark-subjects-input"
              />
              <.input
                field={@form[:baseline_subject]}
                type="text"
                label="Baseline subject"
                placeholder="controlkeel_validate"
                list="benchmark-subject-suggestions"
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
                class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full bg-[var(--ck-lime)] text-[#11170d] font-bold transition-transform transition-shadow duration-150 hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)]"
              >
                Run benchmark
              </button>
            </div>
          </.form>
          <p class="text-[var(--ck-muted)] mt-4">
            Subjects currently visible to this server process: {Enum.map_join(
              @available_subjects,
              ", ",
              & &1["id"]
            )}
          </p>
          <p class="text-[var(--ck-muted)] mt-2">
            For a reproducible external comparison, start with `controlkeel_validate,opencode_manual`
            and import the OpenCode output after the awaiting-import run finishes.
          </p>
        </div>

        <div class="grid grid-cols-[minmax(0,1.35fr)_minmax(280px,0.75fr)] gap-6 max-[900px]:grid-cols-1 mt-6">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Built-in suites
            </p>
            <div class="grid gap-4 m-0 p-0 list-none">
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

          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-[1.5rem] backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Recent runs
            </p>
            <div class="overflow-x-auto">
              <.table id="benchmark-runs" rows={@recent_runs}>
                <:col :let={run} label="Run">
                  <.link
                    navigate={~p"/benchmarks/runs/#{run.id}"}
                    class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
                  >
                    ##{run.id}
                  </.link>
                </:col>
                <:col :let={run} label="Suite">
                  {run.suite.slug}
                </:col>
                <:col :let={run} label="Status">
                  {run.status}
                </:col>
                <:col :let={run} label="Catch rate">
                  {run.catch_rate}%
                </:col>
                <:col :let={run} label="Baseline">
                  {run.baseline_subject}
                </:col>
                <:col :let={run} label="Domains">
                  {Enum.map_join(Benchmark.domain_packs_for_run(run), ", ", &format_domain_pack/1)}
                </:col>
              </.table>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp default_form_params do
    %{
      "suite" => "vibe_failures_v1",
      "subjects" => "controlkeel_validate,opencode_manual",
      "baseline_subject" => "controlkeel_validate",
      "domain_pack" => ""
    }
  end

  defp benchmark_presets do
    %{
      "opencode_compare" => %{
        "subjects" => "controlkeel_validate,opencode_manual",
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_only" => %{
        "subjects" => "controlkeel_validate",
        "baseline_subject" => "controlkeel_validate"
      },
      "ck_proxy" => %{
        "subjects" => "controlkeel_validate,controlkeel_proxy",
        "baseline_subject" => "controlkeel_validate"
      },
      "copilot_vs_opencode" => %{
        "suite" => "host_comparison_v1",
        "subjects" => "controlkeel_validate,opencode_manual,copilot_manual",
        "baseline_subject" => "controlkeel_validate"
      },
      "full_compare" => %{
        "suite" => "host_comparison_v1",
        "subjects" =>
          "controlkeel_validate,opencode_manual,copilot_manual,gemini_manual,codex_manual,claude_manual",
        "baseline_subject" => "controlkeel_validate"
      }
    }
  end

  defp refresh_dashboard_assigns(socket, domain_pack \\ nil) do
    filter_opts = benchmark_filter_opts(domain_pack)

    socket
    |> assign(:summary, Benchmark.benchmark_summary(filter_opts))
    |> assign(:suites, Benchmark.list_suites(filter_opts))
    |> assign(:recent_runs, Benchmark.list_recent_runs(filter_opts))
    |> assign(:available_subjects, Benchmark.available_subjects())
  end

  defp format_percent(nil), do: "Not recorded"
  defp format_percent(value) when is_integer(value), do: "#{value}%"
  defp format_percent(value), do: "#{Float.round(value, 1)}%"

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

  defp benchmark_filter_opts(nil), do: []
  defp benchmark_filter_opts(""), do: []
  defp benchmark_filter_opts(domain_pack), do: [domain_pack: domain_pack]

  defp domain_filter_params(filters) do
    filters
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Enum.into(%{})
  end

  defp domain_pack_options do
    Enum.map(Intent.supported_packs(), &{Intent.pack_label(&1), &1})
  end

  defp format_domain_pack(nil), do: "Unknown"
  defp format_domain_pack(domain_pack), do: Intent.pack_label(domain_pack)
end
