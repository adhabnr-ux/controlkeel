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
      |> assign(:page_action, %{label: "Analyze Project", event: "analyze", icon: "hero-play"})
      |> assign(:project_root, project_root)
      |> assign(:analysis, nil)
      |> assign(:cost_estimates, nil)
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
    <div class="w-full space-y-6">
      <.page_title
        title="Deployment Advisor"
        subtitle="Analyze your project stack, preview deployment files, and estimate hosting costs across major platforms."
      />

      <%= if @analysis do %>
        <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Detected Stack</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {String.capitalize(to_string(@analysis.stack))}
            </p>
          </article>

          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Monthly Cost Range</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              ${@analysis.monthly_cost_range.low} - ${@analysis.monthly_cost_range.high}
            </p>
          </article>

          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Compatible Platforms</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {length(@analysis.platforms)}
            </p>
          </article>

          <article class="rounded-2xl border bg-card p-5 shadow-card">
            <p class="text-sm font-medium text-muted-foreground">Files to Generate</p>
            <p class="mt-2 text-xl font-semibold text-foreground/90">
              {length(@analysis.generators)}
            </p>
          </article>
        </div>

        <section class="space-y-3">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <.section_title>Recommended Platforms</.section_title>

            <div class="flex flex-wrap items-center gap-3 text-sm">
              <label class="flex items-center gap-2 text-muted-foreground">
                Tier
                <select
                  phx-change="select_tier"
                  class="rounded-lg border border-input bg-background px-3 py-1.5 text-sm font-medium text-foreground"
                >
                  <option value="free" selected={@selected_tier == "free"}>Free</option>
                  <option value="hobby" selected={@selected_tier == "hobby"}>Hobby ($5-10/mo)</option>
                  <option value="standard_1x" selected={@selected_tier == "standard_1x"}>
                    Standard ($25/mo)
                  </option>
                  <option value="performance" selected={@selected_tier == "performance"}>
                    Performance ($85+/mo)
                  </option>
                </select>
              </label>

              <label class="flex cursor-pointer items-center gap-2 text-muted-foreground">
                <input
                  type="checkbox"
                  checked={@needs_db}
                  phx-click="toggle_db"
                  class="size-4 rounded border-input bg-background accent-primary"
                /> Database
              </label>

              <button
                type="button"
                phx-click="estimate_costs"
                class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90"
              >
                Estimate Costs
              </button>
            </div>
          </div>

          <%= if @show_costs and @cost_estimates do %>
            <div class="bg-card border rounded-2xl shadow-card overflow-hidden">
              <table class="min-w-full divide-y divide-border text-left text-sm">
                <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
                  <tr>
                    <th class="px-5 py-3 font-semibold">Platform</th>
                    <th class="px-5 py-3 font-semibold">Compute</th>
                    <th class="px-5 py-3 font-semibold">Database</th>
                    <th class="px-5 py-3 font-semibold">Bandwidth</th>
                    <th class="px-5 py-3 font-semibold text-right">Total</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-border">
                  <%= for est <- @cost_estimates do %>
                    <tr class="transition hover:bg-muted/30">
                      <td class="px-5 py-4">
                        <div class="flex items-center gap-2">
                          <span class="font-medium text-foreground">{est.name}</span>
                          <%= if est.fits_stack do %>
                            <span class="inline-flex rounded-full bg-success/10 px-2.5 py-1 text-xs font-semibold text-success ring-1 ring-success/20">
                              Best fit
                            </span>
                          <% end %>
                        </div>
                      </td>
                      <td class="px-5 py-4 text-muted-foreground">
                        ${format_cents(est.breakdown.compute)}/mo
                      </td>
                      <td class="px-5 py-4 text-muted-foreground">
                        ${format_cents(est.breakdown.database)}/mo
                      </td>
                      <td class="px-5 py-4 text-muted-foreground">
                        ${format_cents(est.breakdown.bandwidth)}/mo
                      </td>
                      <td class="px-5 py-4 text-right font-medium text-foreground">
                        ${format_usd(est.total_monthly_usd)}/mo
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% else %>
            <div class="bg-card border rounded-2xl shadow-card overflow-hidden">
              <table class="min-w-full divide-y divide-border text-left text-sm">
                <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
                  <tr>
                    <th class="px-5 py-3 font-semibold">Platform</th>
                    <th class="px-5 py-3 font-semibold">Tier</th>
                    <th class="px-5 py-3 font-semibold">Starting Price</th>
                    <th class="px-5 py-3 font-semibold">Notes</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-border">
                  <%= for p <- @analysis.platforms do %>
                    <tr class="transition hover:bg-muted/30">
                      <td class="px-5 py-4">
                        <a
                          href={p.url}
                          target="_blank"
                          rel="noopener noreferrer"
                          class="font-medium text-foreground transition hover:text-primary"
                        >
                          {p.name}
                        </a>
                      </td>
                      <td class="px-5 py-4 text-muted-foreground">{p.tier.name}</td>
                      <td class="px-5 py-4 text-muted-foreground">
                        <%= if p.tier.monthly_low == 0 do %>
                          Free
                        <% else %>
                          ${p.tier.monthly_low}/mo
                        <% end %>
                      </td>
                      <td class="px-5 py-4 text-muted-foreground">{p.notes}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </section>

        <section class="space-y-3">
          <div class="flex items-center justify-between gap-3">
            <.section_title>Generated Files (Preview)</.section_title>
            <button
              type="button"
              phx-click="generate_files"
              class="inline-flex items-center gap-2 rounded-3xl bg-primary px-4 py-2 text-sm font-semibold text-primary-foreground transition hover:bg-primary/90"
            >
              Preview Files
            </button>
          </div>

          <%= if @generated_files do %>
            <div class="bg-card border rounded-2xl shadow-card overflow-hidden">
              <%= for {:ok, name, path, content, status} <- @generated_files do %>
                <div class="divide-y divide-border">
                  <div class="flex items-center justify-between gap-3 px-5 py-3">
                    <div class="min-w-0">
                      <p class="font-medium text-foreground">{name}</p>
                      <p class="mt-0.5 truncate text-xs text-muted-foreground">{path}</p>
                    </div>
                    <span class={[
                      "inline-flex shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                      status == :written && "bg-success/10 text-success ring-success/20",
                      status == :skipped && "bg-warning/10 text-warning ring-warning/20"
                    ]}>
                      {String.capitalize(to_string(status))}
                    </span>
                  </div>
                  <pre class="max-h-64 overflow-x-auto bg-muted px-5 py-4 font-mono text-xs text-foreground/90"><code phx-no-curly-interpolation>{content}</code></pre>
                </div>
              <% end %>
            </div>
          <% else %>
            <p class="text-sm text-muted-foreground">
              Click "Preview Files" to see what will be generated for your {@analysis.stack} project.
            </p>
          <% end %>
        </section>
      <% else %>
        <div class="rounded-2xl border bg-card p-5 shadow-card">
          <p class="text-sm text-muted-foreground">
            Click "Analyze Project" to detect your project stack and get deployment recommendations.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  defp format_cents(cents), do: :erlang.float_to_binary(cents / 100, decimals: 2)
  defp format_usd(amount), do: :erlang.float_to_binary(amount, decimals: 2)
end
