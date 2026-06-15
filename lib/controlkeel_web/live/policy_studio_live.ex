defmodule ControlKeelWeb.PolicyStudioLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.Intent
  alias ControlKeel.Mission
  alias ControlKeel.Policy.PackLoader

  @impl true
  def mount(_params, session, socket) do
    org_id =
      socket.assigns[:current_org_id] ||
        Map.get(session, "current_org_id") ||
        Map.get(session, :current_org_id)

    {:ok,
     socket
     |> assign(:page_title, "Policy Studio")
     |> assign(:current_org_id, org_id)
     |> assign_packs()
     |> assign_sessions(org_id)
     |> assign_tool_policies(org_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="mx-auto max-w-[1180px] px-4 py-12 pb-16 pt-8">
        <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
          <div>
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Policy Studio
            </p>
            <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Active governance rules</h1>
            <p class="text-[var(--ck-muted)] max-w-3xl text-base leading-relaxed">
              Every agent action passes through these policy packs before it executes. Rules that block are enforced automatically — no action required from you.
            </p>
          </div>
          <a
            href={~p"/"}
            class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
          >
            Back home
          </a>
        </div>

        <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mt-5">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-2xl backdrop-blur-lg shadow-2xl p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Active packs
            </p>
            <strong>{@pack_count}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-2xl backdrop-blur-lg shadow-2xl p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Total rules
            </p>
            <strong>{@rule_count}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-2xl backdrop-blur-lg shadow-2xl p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Blocking rules
            </p>
            <strong>{@block_count}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-2xl backdrop-blur-lg shadow-2xl p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
              Active sessions
            </p>
            <strong>{length(@sessions)}</strong>
          </div>
        </div>

        <div class="grid gap-6 mt-6 max-[900px]:grid-cols-1 min-[901px]:grid-cols-[1.35fr_0.75fr]">
          <div>
            <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-2xl backdrop-blur-lg shadow-2xl p-6">
              <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
                Policy packs
              </p>

              <p class="text-[var(--ck-muted)] text-sm mt-4 mb-6">
                <span class="rounded-full p-2 text-xs bg-red-500/15 text-red-300 border border-red-500/15 mr-1 font-bold uppercase">
                  {@block_count} rules
                </span>
                are block agent actions when violated. Other rules only generate warnings.
              </p>
              <div class="grid gap-4 list-none m-0 p-0">
                <%= for {name, rules} <- @packs do %>
                  <article class="grid gap-[0.55rem] border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)]">
                    <h3>{pack_label(name)}</h3>
                    <p class="text-[var(--ck-muted)]">{pack_description(name)}</p>
                    <div class="flex flex-wrap gap-2 mt-2">
                      <%= for rule <- rules do %>
                        <span
                          title={rule.action <> ", " <> rule.category}
                          class={"border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-[0.8rem] #{rule_tag_class(rule.action)}"}
                        >
                          {rule_name(rule.id)}
                        </span>
                      <% end %>
                    </div>
                  </article>
                <% end %>
              </div>
            </div>
          </div>

          <div>
            <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-2xl backdrop-blur-lg shadow-2xl p-6 mb-4">
              <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
                Session budgets
              </p>
              <%= if @sessions == [] do %>
                <p class="text-[var(--ck-muted)]">
                  No active sessions. Start a mission at <a
                    href={~p"/missions/start"}
                    class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
                  >/missions/start</a>.
                </p>
              <% else %>
                <div class="grid gap-4 list-none m-0 p-0">
                  <%= for session <- @sessions do %>
                    <article class="grid gap-[0.55rem] border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)]">
                      <div class="flex items-center justify-between gap-4">
                        <h3>
                          <.link
                            navigate={~p"/missions/#{session.id}"}
                            class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold"
                          >
                            {session.title}
                          </.link>
                        </h3>
                        <span class={"border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-[0.8rem] #{risk_pill_class(session.risk_tier)}"}>
                          {session.risk_tier}
                        </span>
                      </div>
                      <div class="flex items-center justify-between gap-4 mt-2">
                        <span class="text-[var(--ck-muted)]">
                          Budget: {format_cents(session.budget_cents)}
                        </span>
                        <span class="text-[var(--ck-muted)]">
                          Spent: {format_cents(session.spent_cents)}
                        </span>
                        <span class="text-[var(--ck-muted)]">
                          Daily cap: {format_cents(session.daily_budget_cents)}
                        </span>
                      </div>
                      <%= if (session.budget_cents || 0) > 0 do %>
                        <% pct = budget_pct(session.spent_cents, session.budget_cents) %>
                        <div class="w-full rounded-full bg-[var(--ck-panel)] h-2 mt-2">
                          <div
                            class={"h-full rounded-full transition-all #{budget_fill_class(pct)}"}
                            style={"width: #{pct}%"}
                          >
                          </div>
                        </div>
                      <% end %>
                    </article>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-2xl backdrop-blur-lg shadow-2xl p-6 mt-4">
              <p class="uppercase tracking-[0.14em] text-xs text-[var(--ck-lime)] font-semibold">
                Workspace tool policies
              </p>
              <%= if @tool_policies == [] do %>
                <p class="text-[var(--ck-muted)]">
                  All workspaces inherit global tool access. Set a workspace policy with <code>controlkeel workspace tool-policy set</code>.
                </p>
              <% else %>
                <div class="grid gap-4 list-none m-0 p-0">
                  <%= for {ws, policy} <- @tool_policies do %>
                    <article class="grid gap-[0.55rem] border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)]">
                      <div class="flex items-center justify-between gap-4">
                        <h3>{ws.name}</h3>
                        <span class={"border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-[0.8rem] #{tool_policy_pill_class(policy.mode)}"}>
                          {policy.mode}
                        </span>
                      </div>
                      <% tools = WorkspaceToolPolicy.decode_tools(policy) %>
                      <%= if tools != [] do %>
                        <p class="text-[var(--ck-muted)] mt-1">
                          Tools: {Enum.join(tools, ", ")}
                        </p>
                      <% end %>
                    </article>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp assign_packs(socket) do
    packs = PackLoader.all_packs()
    all_rules = packs |> Map.values() |> List.flatten()

    blocked_rules =
      packs
      |> Enum.map(fn {name, rules} -> {name, Enum.filter(rules, &(&1.action == "block"))} end)
      |> Enum.reject(fn {_name, rules} -> rules == [] end)
      |> Enum.sort_by(fn {name, _} -> pack_sort_order(name) end)

    socket
    |> assign(:packs, Enum.sort_by(packs, fn {name, _} -> pack_sort_order(name) end))
    |> assign(:pack_count, map_size(packs))
    |> assign(:rule_count, length(all_rules))
    |> assign(:block_count, Enum.count(all_rules, &(&1.action == "block")))
    |> assign(:blocked_rules, blocked_rules)
  end

  defp assign_sessions(socket, nil) do
    assign(socket, :sessions, [])
  end

  defp assign_sessions(socket, org_id) when is_integer(org_id) do
    workspaces = Accounts.list_workspaces_for_org(org_id)

    sessions =
      workspaces
      |> Enum.flat_map(fn ws -> Mission.list_sessions_for_workspace(ws.id) end)
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(20)

    assign(socket, :sessions, sessions)
  end

  defp assign_tool_policies(socket, nil) do
    assign(socket, :tool_policies, [])
  end

  defp assign_tool_policies(socket, org_id) when is_integer(org_id) do
    workspaces = Accounts.list_workspaces_for_org(org_id)

    policies =
      workspaces
      |> Enum.map(fn ws ->
        policy = Accounts.get_workspace_tool_policy(ws.id)
        {ws, policy}
      end)
      |> Enum.reject(fn {_ws, policy} -> is_nil(policy) || policy.mode == "inherit" end)

    assign(socket, :tool_policies, policies)
  end

  defp pack_label("baseline"), do: "Baseline — Secrets & OWASP"
  defp pack_label("cost"), do: "Cost — Budget guardrails"
  defp pack_label("software"), do: "Software — Code hygiene"
  defp pack_label("healthcare"), do: "Healthcare — HIPAA / PHI"
  defp pack_label("education"), do: "Education — FERPA / COPPA"
  defp pack_label("finance"), do: "Finance — PCI-DSS / SOX"
  defp pack_label("hr"), do: "HR — EEOC / Employee PII"
  defp pack_label("legal"), do: "Legal — Privilege / Retention"
  defp pack_label("marketing"), do: "Marketing — Consent / CAN-SPAM"
  defp pack_label("sales"), do: "Sales — CRM / Contact PII"
  defp pack_label("realestate"), do: "Real Estate — Transaction / PII"
  defp pack_label("gdpr"), do: "GDPR — EU Data Protection"

  defp pack_label(name) do
    if name in Intent.supported_packs(),
      do: Intent.pack_label(name),
      else: String.capitalize(name)
  end

  defp pack_description("baseline"),
    do: "Always active. Detects secrets, injection, and XSS in all agent output."

  defp pack_description("cost"),
    do: "Always active. Warns at 80% of budget, blocks at 100%."

  defp pack_description("software"),
    do: "Active for software domain. Catches debug endpoints, auth bypass, eval, open CORS."

  defp pack_description("healthcare"),
    do: "Active when domain pack is healthcare. Flags PHI patterns and HIPAA-sensitive data."

  defp pack_description("education"),
    do: "Active when domain pack is education. Flags student data and FERPA-sensitive content."

  defp pack_description("finance"),
    do: "Active when domain pack is finance. Flags payment card data and SOX-sensitive records."

  defp pack_description("hr"),
    do:
      "Active when domain pack is HR. Flags employee PII, candidate data handling, and automated screening risks."

  defp pack_description("legal"),
    do:
      "Active when domain pack is legal. Flags attorney-client privilege risks, unencrypted document handling, and retention violations."

  defp pack_description("marketing"),
    do:
      "Active when domain pack is marketing. Flags missing consent mechanisms, CAN-SPAM violations, and unsecured contact lists."

  defp pack_description("sales"),
    do:
      "Active when domain pack is sales. Flags CRM contact PII, quota audit risks, and data portability gaps."

  defp pack_description("realestate"),
    do:
      "Active when domain pack is real estate. Flags client PII, unencrypted transaction docs, and Fair Housing compliance gaps."

  defp pack_description("gdpr"),
    do:
      "Active for EU data handling. Flags missing consent, right-to-delete gaps, and cross-border data transfer risks."

  defp pack_description(name) when is_binary(name) do
    if name in Intent.supported_packs() do
      pack = Intent.Domains.pack(name)

      "Active when domain pack is #{Intent.pack_label(name)}. Focus areas: #{Enum.join(pack.compliance, ", ")}."
    else
      "Domain-specific policy rules."
    end
  end

  defp pack_description(_), do: "Domain-specific policy rules."

  defp pack_sort_order("baseline"), do: 0
  defp pack_sort_order("cost"), do: 1
  defp pack_sort_order("software"), do: 2
  defp pack_sort_order(_), do: 3

  defp risk_pill_class("critical"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp risk_pill_class("high"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp risk_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp format_cents(nil), do: "not set"
  defp format_cents(0), do: "$0"

  defp format_cents(cents),
    do:
      "$#{div(cents, 100)}.#{rem(cents, 100) |> Integer.to_string() |> String.pad_leading(2, "0")}"

  defp budget_pct(_spent, nil), do: 0
  defp budget_pct(_spent, 0), do: 0
  defp budget_pct(spent, budget), do: min(round((spent || 0) / budget * 100), 100)

  defp budget_fill_class(pct) when pct >= 90, do: "bg-[var(--ck-danger)]"
  defp budget_fill_class(pct) when pct >= 75, do: "bg-[var(--ck-warning)]"
  defp budget_fill_class(_), do: "bg-[var(--ck-success)]"

  defp tool_policy_pill_class("allowlist"), do: "bg-[rgba(125,226,174,0.12)] text-[#7de2ae]"
  defp tool_policy_pill_class("denylist"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp tool_policy_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp rule_name(id) do
    id |> String.split(".") |> List.last() |> String.replace("_", " ")
  end

  defp rule_tag_class("block"), do: "bg-red-500/15 text-red-300 border-red-500/15"
  defp rule_tag_class("warn"), do: "bg-yellow-500/15 text-yellow-300 border-yellow-500/15"
end
