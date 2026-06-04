defmodule ControlKeelWeb.ProviderStatusComponents do
  use ControlKeelWeb, :html

  attr :provider_status, :map, required: true

  def current_status(assigns) do
    ~H"""
    <section class="rounded-3xl border border-white/10 bg-zinc-900/70 p-5 shadow-2xl shadow-black/20 backdrop-blur">
      <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
        Provider and Autonomy Status
      </p>

      <div class="mt-5 grid gap-4 border-t border-white/10 pt-4 sm:grid-cols-2">
        <div>
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Current mode
          </h3>
          <p class="mt-1 text-sm font-medium text-zinc-200">
            {provider_mode_label(@provider_status)}
          </p>
        </div>
        <div>
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Current provider
          </h3>
          <p class="mt-1 text-sm font-medium text-zinc-200">
            {provider_name(@provider_status)}
          </p>
        </div>
        <div>
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Setup scope
          </h3>
          <p class="mt-1 text-sm leading-6 text-zinc-300">
            {setup_scope_copy(@provider_status)}
          </p>
        </div>
        <div>
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Attached agents
          </h3>
          <p class="mt-1 text-sm leading-6 text-zinc-300">
            {attached_agents_copy(@provider_status)}
          </p>
        </div>
      </div>

      <div class="mt-5 rounded-2xl border border-white/10 bg-white/[0.03] p-4">
        <p class="text-sm leading-6 text-zinc-300">{provider_guidance(@provider_status)}</p>
        <p class="mt-3 text-xs italic leading-5 text-zinc-500">
          Autonomy and findings map to human review severity. LLM advisory requires a provider, while validate responses still report advisory status.
          See <code class="font-mono text-[11px] text-zinc-400">docs/autonomy-and-findings.md</code>.
        </p>
      </div>

      <div class="mt-5 grid gap-4 lg:grid-cols-2">
        <div class="rounded-2xl bg-white/[0.04] p-4">
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Always available
          </h3>
          <ul class="mt-3 space-y-2 text-sm text-zinc-300">
            <%= for item <- always_available_capabilities() do %>
              <li>{item}</li>
            <% end %>
          </ul>
        </div>

        <div class="rounded-2xl bg-white/[0.04] p-4">
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Model-backed features
          </h3>
          <ul class="mt-3 space-y-2 text-sm text-zinc-300">
            <%= for item <- model_backed_capabilities(@provider_status) do %>
              <li>{item}</li>
            <% end %>
          </ul>
        </div>
      </div>

      <div class="mt-5 grid gap-4 lg:grid-cols-2">
        <div class="rounded-2xl bg-white/[0.04] p-4">
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Resolution order
          </h3>
          <ol class="mt-3 space-y-2 text-sm text-zinc-300">
            <%= for item <- provider_resolution_steps() do %>
              <li>{item}</li>
            <% end %>
          </ol>
        </div>

        <div class="rounded-2xl bg-white/[0.04] p-4">
          <h3 class="text-[10px] font-semibold uppercase tracking-[0.14em] text-zinc-500">
            Autonomy defaults
          </h3>
          <ul class="mt-3 space-y-2 text-sm text-zinc-300">
            <%= for item <- autonomy_defaults() do %>
              <li>{item}</li>
            <% end %>
          </ul>
        </div>
      </div>
    </section>
    """
  end

  defp provider_mode_label(%{
         "selected_source" => "agent_bridge",
         "selected_provider" => provider
       }) do
    "Bridge via attached agent (#{provider})"
  end

  defp provider_mode_label(%{
         "selected_source" => "workspace_profile",
         "selected_provider" => provider
       }) do
    "Workspace-managed provider (#{provider})"
  end

  defp provider_mode_label(%{
         "selected_source" => "user_default_profile",
         "selected_provider" => provider
       }) do
    "ControlKeel user profile (#{provider})"
  end

  defp provider_mode_label(%{
         "selected_source" => "project_override",
         "selected_provider" => provider
       }) do
    "Project override (#{provider})"
  end

  defp provider_mode_label(%{"selected_source" => "ollama", "selected_model" => model}) do
    "Local Ollama (#{model || "default model"})"
  end

  defp provider_mode_label(_status), do: "Heuristic / no-LLM fallback"

  defp provider_name(%{"selected_provider" => provider}) when provider in [nil, "heuristic"] do
    "No provider selected"
  end

  defp provider_name(%{"selected_provider" => provider, "selected_model" => model}) do
    if blank?(model), do: provider, else: "#{provider} / #{model}"
  end

  defp setup_scope_copy(%{"binding_mode" => mode}) when mode in ["project", "ephemeral"] do
    "Governance stays project-local. Some agent installs can still be user-scoped."
  end

  defp setup_scope_copy(_status) do
    "Use user scope for reusable agent installs. Use project bootstrap for governed repos."
  end

  defp attached_agents_copy(%{"attached_agents" => []}), do: "None yet"

  defp attached_agents_copy(%{"attached_agents" => agents}) when is_list(agents) do
    Enum.map_join(agents, ", ", fn agent ->
      Map.get(agent, "label") || Map.get(agent, "id") || "Unknown"
    end)
  end

  defp attached_agents_copy(_status), do: "None yet"

  defp provider_guidance(%{"selected_source" => "agent_bridge"}) do
    "ControlKeel is borrowing model access from an attached agent bridge, so you usually do not need to enter a separate API key for guided compilation and advisory features."
  end

  defp provider_guidance(%{"selected_source" => source})
       when source in ["workspace_profile", "user_default_profile", "project_override"] do
    "ControlKeel has its own provider profile available. Guided compilation and advisory features can run directly from the configured model source."
  end

  defp provider_guidance(%{"selected_source" => "ollama"}) do
    "ControlKeel is using a local Ollama model. This keeps setup local-first and avoids hosted API keys, but model quality depends on the local model you run."
  end

  defp provider_guidance(_status) do
    "No bridge, API key, or local model is configured right now. ControlKeel still governs agent work, captures proofs, runs MCP tools, and benchmarks outcomes in heuristic mode."
  end

  defp always_available_capabilities do
    [
      "Governance and policy validation on agent actions",
      "Findings, proof bundles, and mission audit trail",
      "MCP tools, skills, and agent attachments",
      "Benchmark runs and policy artifact management"
    ]
  end

  defp model_backed_capabilities(%{"selected_provider" => provider})
       when provider in [nil, "heuristic"] do
    [
      "Execution brief compilation falls back to heuristics or may ask for a provider",
      "Advisory scanner only runs when a provider is available",
      "Model-backed guidance is limited until a bridge, key, or Ollama model is configured"
    ]
  end

  defp model_backed_capabilities(_status) do
    [
      "Execution brief compilation can use the configured model path",
      "Advisory scanner can add model-backed review on top of pattern scanning",
      "Provider-backed guidance can run without asking for another setup step"
    ]
  end

  defp provider_resolution_steps do
    [
      "Attached agent bridge when supported",
      "Workspace or service-account profile",
      "ControlKeel user default profile",
      "Project override",
      "Local Ollama",
      "Heuristic fallback"
    ]
  end

  defp autonomy_defaults do
    [
      "Low-risk guidance continues automatically with warnings when needed",
      "Medium-risk findings stay visible and route the operator toward a fix",
      "Destructive or high-risk actions should be blocked or explicitly reviewed",
      "Governed repos keep the policy trail even when model features degrade"
    ]
  end

  defp blank?(value), do: String.trim(to_string(value || "")) == ""

  attr :provider_status, :map, required: true

  def provider_bootstrap_detail(assigns) do
    ~H"""
    <section
      id="skills-provider-status"
      class="rounded-3xl border border-white/10 bg-zinc-900/70 p-5 shadow-2xl shadow-black/20 backdrop-blur"
    >
      <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
        Provider and bootstrap status
      </p>
      <div class="mt-5 grid gap-4 border-t border-white/10 pt-4">
        <article class="rounded-2xl border border-white/10 bg-white/[0.03] p-4 grid gap-[0.55rem]">
          <div class="flex items-center justify-between gap-4">
            <h3 class="text-sm font-semibold text-zinc-200">Active provider</h3>
            <span class="rounded-full border border-white/10 bg-white/[0.06] px-3 py-[0.45rem] text-xs text-lime-300">
              {@provider_status["selected_source"]}
            </span>
          </div>
          <p class="text-sm text-zinc-400">
            Provider: {@provider_status["selected_provider"]} / {@provider_status["selected_model"] ||
              "default"}
          </p>
          <p class="text-sm text-zinc-400">
            Base URL: {selected_base_url(@provider_status)}
          </p>
          <p class="text-sm text-zinc-400">
            Auth: {@provider_status["selected_auth_mode"]} / {@provider_status["selected_auth_owner"]}
          </p>
          <p class="text-sm text-zinc-400">
            Bootstrap mode: {@provider_status["bootstrap"]["mode"]}
          </p>
          <p class="text-sm text-zinc-400">
            Fallback chain: {Enum.join(@provider_status["fallback_chain"], ", ")}
          </p>
        </article>
      </div>
    </section>
    """
  end

  attr :registry_status, :map, required: true

  def registry_cache(assigns) do
    ~H"""
    <section class="rounded-3xl border border-white/10 bg-zinc-900/70 p-5 shadow-2xl shadow-black/20 backdrop-blur">
      <p class="text-xs font-semibold uppercase tracking-[0.18em] text-lime-300">
        ACP registry cache
      </p>
      <div class="mt-5 grid gap-4 border-t border-white/10 pt-4">
        <article
          class="rounded-2xl border border-white/10 bg-white/[0.03] p-4 grid gap-[0.55rem]"
          id="skills-registry-status"
        >
          <div class="flex items-center justify-between gap-4">
            <h3 class="text-sm font-semibold text-zinc-200">Cache status</h3>
            <span class={[
              "rounded-full border px-3 py-[0.45rem] text-xs",
              (@registry_status["stale"] && "border-amber-200/20 bg-amber-300/10 text-amber-100") ||
                "border-white/10 bg-white/[0.06] text-lime-300"
            ]}>
              {if @registry_status["stale"], do: "stale", else: "fresh"}
            </span>
          </div>
          <p class="text-sm text-zinc-400">
            Entries: {@registry_status["entry_count"]} / matched integrations: {@registry_status[
              "matched_integrations"
            ]}
          </p>
          <p class="text-sm text-zinc-400">
            Fetched at: {@registry_status["fetched_at"] || "never"}
          </p>
        </article>
      </div>
    </section>
    """
  end

  defp selected_base_url(%{"provider_chain" => [resolution | _]}) do
    resolution["base_url"] || "default"
  end

  defp selected_base_url(_status), do: "default"
end
