defmodule ControlKeelWeb.DeploymentLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Ops.DeploymentAdvisor, as: Advisor
  alias ControlKeel.Ops.HostingCost

  @impl true
  def mount(_params, _session, socket) do
    project_root = socket.endpoint.config(:project_root) || File.cwd!()

    socket =
      socket
      |> assign(:page_title, "Deployment Advisor")
      |> assign(:project_root, project_root)
      |> assign(:analysis, nil)
      |> assign(:cost_estimates, nil)
      |> assign(:generating, false)
      |> assign(:generated_files, nil)
      |> assign(:selected_tier, "free")
      |> assign(:needs_db, true)
      |> assign(:show_costs, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("analyze", _params, socket) do
    {:ok, analysis} = Advisor.analyze(socket.assigns.project_root)
    {:noreply, assign(socket, :analysis, analysis)}
  end

  @impl true
  def handle_event("estimate_costs", _params, socket) do
    tier = String.to_atom(socket.assigns.selected_tier)

    {:ok, estimates} =
      HostingCost.estimate(
        stack: socket.assigns.analysis.stack,
        tier: tier,
        needs_db: socket.assigns.needs_db,
        expected_bandwidth_gb: 10,
        expected_storage_gb: 1
      )

    {:noreply, assign(socket, cost_estimates: estimates, show_costs: true)}
  end

  @impl true
  def handle_event("toggle_db", _params, socket) do
    {:noreply, assign(socket, :needs_db, not socket.assigns.needs_db)}
  end

  @impl true
  def handle_event("select_tier", %{"tier" => tier}, socket) do
    {:noreply, assign(socket, :selected_tier, tier)}
  end

  @impl true
  def handle_event("generate_files", _params, socket) do
    {:ok, results} =
      Advisor.generate_files(
        socket.assigns.project_root,
        socket.assigns.analysis.generators,
        dry_run: true
      )

    {:noreply, assign(socket, :generated_files, results)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16 max-[900px]:w-[min(100%-1.25rem,1180px)] max-[900px]:pt-6">
      <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
        <div>
          <p class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
            Deployment
          </p>
          <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Deployment Advisor</h1>
          <p class="text-[var(--muted-foreground)] text-[1.05rem] leading-[1.7] max-w-[48rem]">
            Analyze your project stack, preview deployment files, and estimate hosting costs across major platforms.
          </p>
        </div>
        <div class="flex items-center justify-between gap-4">
          <button phx-click="analyze">
            Analyze Project
          </button>
          <a
            href={~p"/"}
            class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold"
          >
            Back home
          </a>
        </div>
      </div>

      <%= if @analysis do %>
        <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mt-5">
          <div class="border border-[var(--border)] bg-[var(--card)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
              Detected Stack
            </p>
            <strong class="text-lg">{String.capitalize(to_string(@analysis.stack))}</strong>
          </div>
          <div class="border border-[var(--border)] bg-[var(--card)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
              Monthly Cost Range
            </p>
            <strong>
              ${@analysis.monthly_cost_range.low} - ${@analysis.monthly_cost_range.high}
            </strong>
          </div>
          <div class="border border-[var(--border)] bg-[var(--card)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
              Compatible Platforms
            </p>
            <strong>{length(@analysis.platforms)}</strong>
          </div>
          <div class="border border-[var(--border)] bg-[var(--card)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
              Files to Generate
            </p>
            <strong>{length(@analysis.generators)}</strong>
          </div>
        </div>

        <div class="border border-[var(--border)] bg-[var(--card)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <div class="flex items-center justify-between mb-4">
            <h2>Recommended Platforms</h2>
            <div class="flex gap-2 items-center">
              <label class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold">
                Tier:
              </label>
              <select phx-change="select_tier" class="text-sm" style="width:auto">
                <option value="free" selected={@selected_tier == "free"}>Free</option>
                <option value="hobby" selected={@selected_tier == "hobby"}>Hobby ($5-10/mo)</option>
                <option value="standard_1x" selected={@selected_tier == "standard_1x"}>
                  Standard ($25/mo)
                </option>
                <option value="performance" selected={@selected_tier == "performance"}>
                  Performance ($85+/mo)
                </option>
              </select>
              <label class="flex items-center gap-1 text-sm">
                <input type="checkbox" checked={@needs_db} phx-click="toggle_db" class="rounded" />
                Database
              </label>
              <button phx-click="estimate_costs">
                Estimate Costs
              </button>
            </div>
          </div>

          <%= if @show_costs and @cost_estimates do %>
            <div class="overflow-x-auto">
              <.table id="cost-estimates" rows={@cost_estimates}>
                <:col :let={est} label="Platform">
                  <div>
                    <strong>{est.name}</strong>
                    <%= if est.fits_stack do %>
                      <span class="inline-block ml-2 px-1.5 py-0.5 text-xs rounded bg-green-100 text-green-800">
                        Best fit
                      </span>
                    <% end %>
                  </div>
                </:col>
                <:col :let={est} label="Compute">
                  ${:erlang.float_to_binary(est.breakdown.compute / 100, decimals: 2)}/mo
                </:col>
                <:col :let={est} label="Database">
                  ${:erlang.float_to_binary(est.breakdown.database / 100, decimals: 2)}/mo
                </:col>
                <:col :let={est} label="Bandwidth">
                  ${:erlang.float_to_binary(est.breakdown.bandwidth / 100, decimals: 2)}/mo
                </:col>
                <:col :let={est} label="Total">
                  <strong>${:erlang.float_to_binary(est.total_monthly_usd, decimals: 2)}/mo</strong>
                </:col>
              </.table>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <.table id="platform-list" rows={@analysis.platforms}>
                <:col :let={p} label="Platform">
                  <a
                    href={p.url}
                    target="_blank"
                    class="uppercase tracking-[0.14em] text-xs text-[var(--primary)] font-semibold"
                  >
                    {p.name}
                  </a>
                </:col>
                <:col :let={p} label="Tier">
                  {p.tier.name}
                </:col>
                <:col :let={p} label="Starting Price">
                  <%= if p.tier.monthly_low == 0 do %>
                    Free
                  <% else %>
                    ${p.tier.monthly_low}/mo
                  <% end %>
                </:col>
                <:col :let={p} label="Notes">
                  <span class="text-sm text-gray-600">{p.notes}</span>
                </:col>
              </.table>
            </div>
          <% end %>
        </div>

        <div class="border border-[var(--border)] bg-[var(--card)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <div class="flex items-center justify-between mb-4">
            <h2>Generated Files (Preview)</h2>
            <div class="flex gap-2">
              <button phx-click="generate_files">
                Preview Files
              </button>
            </div>
          </div>

          <%= if @generated_files do %>
            <div class="space-y-4">
              <%= for {:ok, name, path, content, status} <- @generated_files do %>
                <div class="border rounded-lg overflow-hidden">
                  <div class="flex items-center justify-between px-4 py-2 bg-gray-50 border-b">
                    <div>
                      <strong class="text-sm">{name}</strong>
                      <span class="ml-2 text-xs text-gray-500">{path}</span>
                    </div>
                    <span class={[
                      "text-xs px-2 py-0.5 rounded",
                      status == :written && "bg-green-100 text-green-800",
                      status == :skipped && "bg-yellow-100 text-yellow-800"
                    ]}>
                      {String.capitalize(to_string(status))}
                    </span>
                  </div>
                  <pre class="p-4 text-xs overflow-x-auto bg-gray-900 text-green-400 max-h-64"><code phx-no-curly-interpolation>{content}</code></pre>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-gray-500 text-sm">
              Click "Preview Files" to see what will be generated for your {@analysis.stack} project.
            </p>
          <% end %>
        </div>
      <% else %>
        <div class="border border-[var(--border)] bg-[var(--card)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <p class="text-gray-500">
            Click "Analyze Project" to detect your project stack and get deployment recommendations.
          </p>
        </div>
      <% end %>
    </section>
    """
  end
end
