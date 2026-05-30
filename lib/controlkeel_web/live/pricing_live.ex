defmodule ControlKeelWeb.PricingLive do
  @moduledoc """
  Public pricing page at `/pricing`.

  Shows three tiers: Free (local single-user), Pro (cloud teams), and
  Enterprise (SSO, audit, custom). No auth required.
  """

  use ControlKeelWeb, :live_view

  defp tiers do
    [
    %{
      name: "Free",
      price: "$0",
      period: "forever",
      description: "Local-first governance for individual developers.",
      cta: "Get started",
      cta_link: "/signup",
      highlighted: false,
      features: [
        "Unlimited local projects",
        "Policy-as-code governance",
        "Finding & proof tracking",
        "Benchmark suites",
        "Security review workflows",
        "CLI + IDE integrations"
      ]
    },
    %{
      name: "Pro",
      price: "$29",
      period: "/seat/mo",
      description: "Cloud governance for teams that ship fast.",
      cta: "Start free trial",
      cta_link: "/signup?plan=pro",
      highlighted: true,
      features: [
        "Everything in Free",
        "Cloud sync & multi-device",
        "Team collaboration",
        "Organization management",
        "Shared policy sets",
        "Usage metering & budgets",
        "Workspace API keys",
        "Webhooks & integrations",
        "Priority support"
      ]
    },
    %{
      name: "Enterprise",
      price: "Custom",
      period: "",
      description: "Compliance-grade governance at organizational scale.",
      cta: "Contact sales",
      cta_link: "mailto:sales@controlkeel.com",
      highlighted: false,
      features: [
        "Everything in Pro",
        "SAML / SSO",
        "Audit log export",
        "Custom retention policies",
        "Dedicated support",
        "SLA guarantees",
        "On-premise deployment",
        "Custom integrations"
      ]
    }
  ]
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Pricing — ControlKeel") |> assign(:tiers, tiers())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 1120px; margin: 4rem auto;">
        <div class="text-center mb-12">
          <h1 class="text-4xl font-bold text-white mb-4">Simple, transparent pricing</h1>
          <p class="text-lg text-zinc-400 max-w-2xl mx-auto">
            Start free with local governance. Upgrade to Pro when your team needs cloud sync and collaboration.
          </p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-16">
          <%= for tier <- @tiers do %>
            <div class={
              classes([
                "rounded-xl border p-8 flex flex-col",
                if(tier.highlighted,
                  do: "border-indigo-500/50 bg-indigo-500/5 shadow-lg shadow-indigo-500/10",
                  else: "border-white/10 bg-zinc-900"
                )
              ])
            }>
              <h2 class="text-xl font-semibold text-white mb-1">{tier.name}</h2>
              <p class="text-sm text-zinc-400 mb-4">{tier.description}</p>

              <div class="mb-6">
                <span class="text-4xl font-bold text-white">{tier.price}</span>
                <span class="text-zinc-400">{tier.period}</span>
              </div>

              <.link
                navigate={String.starts_with?(tier.cta_link, "/") && tier.cta_link || nil}
                href={!String.starts_with?(tier.cta_link, "/") && tier.cta_link || nil}
                class={
                  classes([
                    "block text-center rounded-lg px-6 py-3 font-medium transition-colors mb-8",
                    if(tier.highlighted,
                      do: "bg-indigo-600 hover:bg-indigo-500 text-white",
                      else: "bg-zinc-800 hover:bg-zinc-700 text-zinc-200"
                    )
                  ])
                }
              >
                {tier.cta}
              </.link>

              <ul class="space-y-3 flex-1">
                <%= for feature <- tier.features do %>
                  <li class="flex items-start gap-2 text-sm text-zinc-300">
                    <span class="text-indigo-400 mt-0.5">✓</span>
                    {feature}
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>

        <div class="text-center">
          <p class="text-sm text-zinc-500">
            All plans include the full governance engine — findings, proofs, policies, and benchmarks.
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp classes(list) when is_list(list) do
    list
    |> Enum.flat_map(fn
      nil -> []
      item when is_binary(item) -> [item]
      list when is_list(list) -> [Enum.join(list, " ")]
    end)
    |> Enum.join(" ")
  end
end
