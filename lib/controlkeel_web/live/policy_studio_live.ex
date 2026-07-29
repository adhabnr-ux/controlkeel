defmodule ControlKeelWeb.PolicyStudioLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Accounts
  alias ControlKeel.Accounts.WorkspaceToolPolicy
  alias ControlKeel.Intent
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
     |> assign(:open_packs, MapSet.new())
     |> assign_packs()
     |> assign_tool_policies(org_id)}
  end

  @impl true
  def handle_event("toggle_pack", %{"name" => name}, socket) do
    if MapSet.member?(socket.assigns.pack_names, name) do
      open_packs = socket.assigns.open_packs

      open_packs =
        if MapSet.member?(open_packs, name) do
          MapSet.delete(open_packs, name)
        else
          MapSet.put(open_packs, name)
        end

      {:noreply, assign(socket, :open_packs, open_packs)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-[1180px] px-4 py-12 pb-16 pt-8">
      <div class="space-y-1 mb-12">
        <h2 class="text-2xl font-semibold text-primary leading-6 tracking-wide uppercase">
          Policy Studio
        </h2>
        <p class="text-muted-foreground">
          Every agent action passes through these policy packs before it executes. Rules that block are enforced automatically — no action required from you.
        </p>
      </div>

      <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mt-5">
        <div class="border border-border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Active packs
          </p>
          <strong>{@pack_count}</strong>
        </div>
        <div class="border border-border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Total rules
          </p>
          <strong>{@rule_count}</strong>
        </div>
        <div class="border border-border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Blocking rules
          </p>
          <strong>{@block_count}</strong>
        </div>
      </div>

      <div class="grid gap-6 mt-6 max-[900px]:grid-cols-1 min-[901px]:grid-cols-[1.35fr_0.75fr]">
        <div>
          <div class="border border-border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
              Policy packs
            </p>
            <p class="text-muted-foreground text-sm mt-4 mb-4">
              <span class="rounded-full p-2 text-xs bg-red-500/15 text-red-300 border border-red-500/15 mr-1 font-bold uppercase">
                {@block_count} rules
              </span>
              block agent actions when violated. Other rules only generate warnings.
            </p>

            <div class="grid gap-2 list-none m-0 p-0 max-h-[48rem] overflow-y-auto pr-1">
              <%= for {name, rules} <- @packs do %>
                <% open? = MapSet.member?(@open_packs, name) %>
                <article class="border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] bg-[rgba(255,255,255,0.03)]">
                  <% panel_id = "pack-panel-#{name}"
                  label_id = "#{panel_id}-label" %>
                  <h3 class="m-0">
                    <button
                      type="button"
                      phx-click="toggle_pack"
                      phx-value-name={name}
                      aria-expanded={open?}
                      aria-controls={panel_id}
                      class="flex w-full items-center justify-between gap-4 p-4 cursor-pointer select-none text-left"
                    >
                      <span id={label_id}>{pack_label(name)}</span>
                      <span class="flex items-center gap-2">
                        <span class="text-xs text-muted-foreground">
                          {length(rules)} rules
                        </span>
                        <svg
                          aria-hidden="true"
                          class={"w-4 h-4 text-muted-foreground transition-transform duration-200 #{if open?, do: "rotate-180", else: ""}"}
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke="currentColor"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M19 9l-7 7-7-7"
                          />
                        </svg>
                      </span>
                    </button>
                  </h3>
                  <%= if open? do %>
                    <div id={panel_id} role="region" aria-labelledby={label_id} class="px-4 pb-4">
                      <p class="text-muted-foreground text-sm">{pack_description(name)}</p>
                      <div class="flex flex-wrap gap-2 mt-3">
                        <%= for rule <- rules do %>
                          <span
                            title={rule.action <> ", " <> rule.category}
                            class={"border border-border rounded-full px-3 py-[0.45rem] text-[0.8rem] #{rule_tag_class(rule.action)}"}
                          >
                            {rule_name(rule.id)}
                          </span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </article>
              <% end %>
            </div>
          </div>
        </div>

        <div>
          <div class="border border-border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
              Workspace tool policies
            </p>
            <%= if @tool_policies == [] do %>
              <p class="text-muted-foreground">
                All workspaces inherit global tool access. Set a workspace policy with <code>controlkeel workspace tool-policy set</code>.
              </p>
            <% else %>
              <div class="grid gap-4 list-none m-0 p-0">
                <%= for {ws, policy} <- @tool_policies do %>
                  <article class="grid gap-[0.55rem] border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)]">
                    <div class="flex items-center justify-between gap-4">
                      <h3>{ws.name}</h3>
                      <span class={"border border-border rounded-full px-3 py-[0.45rem] text-[0.8rem] #{tool_policy_pill_class(policy.mode)}"}>
                        {policy.mode}
                      </span>
                    </div>
                    <% tools = WorkspaceToolPolicy.decode_tools(policy) %>
                    <%= if tools != [] do %>
                      <p class="text-muted-foreground mt-1">
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
    |> assign(:pack_names, MapSet.new(Map.keys(packs)))
    |> assign(:pack_count, map_size(packs))
    |> assign(:rule_count, length(all_rules))
    |> assign(:block_count, Enum.count(all_rules, &(&1.action == "block")))
    |> assign(:blocked_rules, blocked_rules)
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

  defp tool_policy_pill_class("allowlist"), do: "bg-[rgba(125,226,174,0.12)] text-[#7de2ae]"
  defp tool_policy_pill_class("denylist"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp tool_policy_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp rule_name(id) do
    id |> String.split(".") |> List.last() |> String.replace("_", " ")
  end

  defp rule_tag_class("block"), do: "bg-red-500/15 text-red-300 border-red-500/15"
  defp rule_tag_class("warn"), do: "bg-yellow-500/15 text-yellow-300 border-yellow-500/15"
end
