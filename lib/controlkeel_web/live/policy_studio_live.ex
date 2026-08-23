defmodule ControlKeelWeb.PolicyStudioLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Platform
  alias ControlKeel.Policy.PackLoader

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Policy Studio")
     |> assign(:open_packs, MapSet.new())
     |> assign_packs()
     |> assign_policy_sets()}
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
        <div class="border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Active packs
          </p>
          <strong>{@pack_count}</strong>
        </div>
        <div class="border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Total rules
          </p>
          <strong>{@rule_count}</strong>
        </div>
        <div class="border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Blocking rules
          </p>
          <strong>{@block_count}</strong>
        </div>
      </div>

      <div class="border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6 my-4">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Policy sets
        </p>

        <%= if @policy_sets == [] do %>
          <p class="text-muted-foreground">
            No custom policy sets yet. Create one with <code>controlkeel policy-set create</code>.
          </p>
        <% else %>
          <div class="grid gap-4 list-none m-0 p-0">
            <%= for set <- @policy_sets do %>
              <article class="grid gap-[0.55rem] border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)]">
                <div class="flex items-center justify-between gap-4">
                  <h3>#{set.id} {set.name}</h3>
                  <span
                    title={set.status}
                    class={"border rounded-full px-3 py-[0.45rem] text-[0.8rem] #{status_pill_class(set.status)}"}
                  >
                    {set.status}
                  </span>
                </div>
                <p class="text-muted-foreground mt-1">
                  {length(Platform.PolicySet.rule_entries(set))} rules · scope: {set.scope}
                  <%= if set.description not in [nil, ""] do %>
                    · {set.description}
                  <% end %>
                </p>
                <%= if set.workspace_policy_sets != [] do %>
                  <p class="text-muted-foreground text-sm">
                    Applied to:
                    <%= for assignment <- set.workspace_policy_sets do %>
                      workspace #{assignment.workspace_id} (precedence {assignment.precedence}
                      <%= unless assignment.enabled do %>
                        , disabled
                      <% end %>)<%= if assignment != List.last(set.workspace_policy_sets) do %>
                        ,
                      <% end %>
                    <% end %>
                  </p>
                <% else %>
                  <p class="text-muted-foreground text-sm">Not applied to any workspace yet.</p>
                <% end %>
              </article>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="border bg-card rounded-2xl backdrop-blur-lg shadow-2xl p-6">
        <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
          Policy packs
        </p>
        <p class="text-muted-foreground text-sm mt-4 mb-4">
          <span class="rounded-full p-2 text-xs bg-destructive/15 text-destructive border border-destructive/15 mr-1 font-bold uppercase">
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
                        class={"border rounded-full px-3 py-[0.45rem] text-[0.8rem] #{rule_tag_class(rule.action)}"}
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

  defp assign_policy_sets(socket) do
    assignments_by_set =
      Platform.list_workspace_policy_sets()
      |> Enum.group_by(& &1.policy_set_id)

    policy_sets =
      Platform.list_policy_sets()
      |> Enum.map(fn set ->
        Map.put(set, :workspace_policy_sets, Map.get(assignments_by_set, set.id, []))
      end)

    assign(socket, :policy_sets, policy_sets)
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

  defp status_pill_class("active"), do: "bg-[rgba(125,226,174,0.12)] text-[#7de2ae]"
  defp status_pill_class("disabled"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp status_pill_class("archived"), do: "bg-muted text-muted-foreground"
  defp status_pill_class(_), do: "bg-muted text-muted-foreground"

  defp rule_name(id) do
    id |> String.split(".") |> List.last() |> String.replace("_", " ")
  end

  defp rule_tag_class("block"), do: "bg-destructive/15 text-destructive border-destructive/15"

  defp rule_tag_class("warn"),
    do: "bg-[var(--ck-warning)]/15 text-[var(--ck-warning)] border-[var(--ck-warning)]/15"
end
