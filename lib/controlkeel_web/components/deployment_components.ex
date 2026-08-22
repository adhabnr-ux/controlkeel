defmodule ControlKeelWeb.DeploymentComponents do
  @moduledoc """
  Deployment advisor modal rendered from the session page. Events
  (`deploy_analyze`, `close_deploy`, `select_tier`, `toggle_db`,
  `estimate_costs`, `preview_files`) are handled by the parent LiveView.
  """

  use Phoenix.Component

  import ControlKeelWeb.CoreComponents, only: [button: 1, icon: 1]

  attr :analysis, :map, default: nil
  attr :unavailable, :boolean, default: false
  attr :cost_estimates, :list, default: nil
  attr :selected_tier, :string, default: "free"
  attr :needs_db, :boolean, default: true
  attr :generated_files, :list, default: nil

  def deploy_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-click-away="close_deploy"
      phx-key="Escape"
      phx-key-target="window"
    >
      <div class="fixed inset-0 bg-overlay/60" phx-click="close_deploy"></div>
      <div class="relative w-full max-w-5xl max-h-[85vh] flex flex-col overflow-hidden rounded-3xl border bg-card shadow-[0_24px_80px_rgba(0,0,0,0.22)]">
        <button
          type="button"
          class="absolute top-5 right-5 z-10 text-muted-foreground hover:text-foreground transition cursor-pointer"
          phx-click="close_deploy"
        >
          <.icon name="hero-x-mark" class="w-5 h-5" />
        </button>

        <div class="flex-1 min-h-0 overflow-y-auto px-6 py-6 space-y-6">
          <div class="pr-8">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary">
              Deploy
            </p>
            <h3 class="text-lg font-semibold text-foreground mt-1">Deployment advisor</h3>
            <p class="text-sm text-muted-foreground">
              Stack detection, platform recommendations, cost estimates, and file previews for this session's project.
            </p>
          </div>

          <%= if @unavailable do %>
            <div class="rounded-2xl border bg-card p-5">
              <p class="text-sm font-medium text-foreground">
                This session's project is not available on this machine.
              </p>
              <p class="mt-1 text-sm text-muted-foreground">
                ControlKeel could not resolve a project root on disk for this session, so deployment analysis cannot run here. From your machine, run:
              </p>
              <code class="mt-3 inline-block font-mono bg-muted px-2 py-1 rounded text-xs text-foreground">
                controlkeel deploy analyze --project-root &lt;path&gt;
              </code>
            </div>
          <% else %>
            <div class="grid grid-cols-2 lg:grid-cols-4 gap-4">
              <article class="rounded-2xl border bg-card p-4">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Detected stack
                </p>
                <p class="mt-1.5 text-xl font-semibold text-foreground/90">
                  {String.capitalize(to_string(@analysis.stack))}
                </p>
              </article>
              <article class="rounded-2xl border bg-card p-4">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Monthly cost range
                </p>
                <p class="mt-1.5 text-xl font-semibold text-foreground/90">
                  ${@analysis.monthly_cost_range.low} - ${@analysis.monthly_cost_range.high}
                </p>
              </article>
              <article class="rounded-2xl border bg-card p-4">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Compatible platforms
                </p>
                <p class="mt-1.5 text-xl font-semibold text-foreground/90">
                  {length(@analysis.platforms)}
                </p>
              </article>
              <article class="rounded-2xl border bg-card p-4">
                <p class="text-xs font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                  Files to generate
                </p>
                <p class="mt-1.5 text-xl font-semibold text-foreground/90">
                  {length(@analysis.generators)}
                </p>
              </article>
            </div>

            <section class="space-y-3">
              <div class="flex flex-wrap items-center justify-between gap-3">
                <h4 class="text-sm font-semibold uppercase tracking-[0.14em] text-primary">
                  Recommended platforms
                </h4>

                <div class="flex flex-wrap items-center gap-3 text-sm">
                  <label class="flex items-center gap-2 text-muted-foreground">
                    Tier
                    <select
                      phx-change="select_tier"
                      class="rounded-lg border border-input bg-background px-3 py-1.5 text-sm font-medium text-foreground cursor-pointer"
                    >
                      <option value="free" selected={@selected_tier == "free"}>Free</option>
                      <option value="hobby" selected={@selected_tier == "hobby"}>
                        Hobby ($5-10/mo)
                      </option>
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

                  <.button phx-click="estimate_costs">
                    Estimate costs
                  </.button>
                </div>
              </div>

              <%= if @cost_estimates do %>
                <div class="border rounded-2xl overflow-hidden">
                  <table class="min-w-full divide-y divide-border text-left text-sm">
                    <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
                      <tr>
                        <th class="px-4 py-2.5 font-semibold">Platform</th>
                        <th class="px-4 py-2.5 font-semibold">Compute</th>
                        <th class="px-4 py-2.5 font-semibold">Database</th>
                        <th class="px-4 py-2.5 font-semibold">Bandwidth</th>
                        <th class="px-4 py-2.5 font-semibold text-right">Total</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-border">
                      <%= for est <- @cost_estimates do %>
                        <tr class="transition hover:bg-muted/30">
                          <td class="px-4 py-3">
                            <div class="flex items-center gap-2">
                              <span class="font-medium text-foreground">{est.name}</span>
                              <%= if est.fits_stack do %>
                                <span class="inline-flex rounded-full bg-success/10 px-2 py-0.5 text-xs font-semibold text-success ring-1 ring-success/20">
                                  Best fit
                                </span>
                              <% end %>
                            </div>
                          </td>
                          <td class="px-4 py-3 text-muted-foreground">
                            ${format_cents(est.breakdown.compute)}/mo
                          </td>
                          <td class="px-4 py-3 text-muted-foreground">
                            ${format_cents(est.breakdown.database)}/mo
                          </td>
                          <td class="px-4 py-3 text-muted-foreground">
                            ${format_cents(est.breakdown.bandwidth)}/mo
                          </td>
                          <td class="px-4 py-3 text-right font-medium text-foreground">
                            ${format_usd(est.total_monthly_usd)}/mo
                          </td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% else %>
                <div class="border rounded-2xl overflow-hidden">
                  <table class="min-w-full divide-y divide-border text-left text-sm">
                    <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
                      <tr>
                        <th class="px-4 py-2.5 font-semibold">Platform</th>
                        <th class="px-4 py-2.5 font-semibold">Tier</th>
                        <th class="px-4 py-2.5 font-semibold">Starting price</th>
                        <th class="px-4 py-2.5 font-semibold">Notes</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-border">
                      <%= for p <- @analysis.platforms do %>
                        <tr class="transition hover:bg-muted/30">
                          <td class="px-4 py-3">
                            <a
                              href={p.url}
                              target="_blank"
                              rel="noopener noreferrer"
                              class="font-medium text-foreground transition hover:text-primary"
                            >
                              {p.name}
                            </a>
                          </td>
                          <td class="px-4 py-3 text-muted-foreground">{p.tier.name}</td>
                          <td class="px-4 py-3 text-muted-foreground">
                            <%= if p.tier.monthly_low == 0 do %>
                              Free
                            <% else %>
                              ${p.tier.monthly_low}/mo
                            <% end %>
                          </td>
                          <td class="px-4 py-3 text-muted-foreground">{p.notes}</td>
                        </tr>
                      <% end %>
                    </tbody>
                  </table>
                </div>
              <% end %>
            </section>

            <section class="space-y-3">
              <div class="flex items-center justify-between gap-3">
                <h4 class="text-sm font-semibold uppercase tracking-[0.14em] text-primary">
                  Generated files (preview)
                </h4>
                <.button phx-click="preview_files">
                  Preview files
                </.button>
              </div>

              <%= if @generated_files do %>
                <div class="border rounded-2xl overflow-hidden divide-y divide-border">
                  <%= for {:ok, name, path, content, status} <- @generated_files do %>
                    <div class="divide-y divide-border">
                      <div class="flex items-center justify-between gap-3 px-4 py-3">
                        <div class="min-w-0">
                          <p class="font-medium text-foreground">{name}</p>
                          <p class="mt-0.5 truncate text-xs text-muted-foreground">{path}</p>
                        </div>
                        <div class="flex shrink-0 items-center gap-2">
                          <.button
                            variant="secondary"
                            phx-click="copy_generated_file"
                            phx-value-name={name}
                          >
                            <.icon name="hero-clipboard-document" class="size-3.5" /> Copy
                          </.button>
                          <span class={[
                            "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1",
                            status == :written && "bg-success/10 text-success ring-success/20",
                            status == :skipped && "bg-warning/10 text-warning ring-warning/20"
                          ]}>
                            {String.capitalize(to_string(status))}
                          </span>
                        </div>
                      </div>
                      <pre class="max-h-64 overflow-x-auto bg-muted px-4 py-3 font-mono text-xs text-foreground/90"><code>{content}</code></pre>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <p class="text-sm text-muted-foreground">
                  Click "Preview files" to see what will be generated for your {@analysis.stack} project.
                </p>
              <% end %>
            </section>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp format_cents(cents), do: :erlang.float_to_binary(cents / 100, decimals: 2)
  defp format_usd(amount), do: :erlang.float_to_binary(amount, decimals: 2)
end
