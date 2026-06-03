defmodule ControlKeelWeb.SkillsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.ACPRegistry
  alias ControlKeel.ProviderBroker
  alias ControlKeel.Skills

  @impl true
  def mount(_params, _session, socket) do
    project_root = File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Skills Studio")
     |> assign(:selected, nil)
     |> assign(:last_result, nil)
     |> assign(:agent_integrations, Skills.agent_integrations())
     |> assign(:target_options, target_options())
     |> assign(:scope_options, [{"Export", "export"}, {"User", "user"}, {"Project", "project"}])
     |> assign_analysis(project_root)
     |> assign(:project_form, project_form(project_root))
     |> assign(:action_form, action_form())}
  end

  @impl true
  def handle_event("select_skill", %{"name" => name}, socket) do
    selected = Enum.find(socket.assigns.skills, &(&1.name == name))
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("validate_project", %{"project" => %{"project_root" => project_root}}, socket) do
    project_root = String.trim(project_root)

    {:noreply,
     socket
     |> assign_analysis(project_root)
     |> assign(:project_form, project_form(project_root))
     |> assign(:selected, nil)}
  end

  def handle_event("update_action_form", %{"skill_action" => params}, socket) do
    {:noreply, assign(socket, :action_form, action_form(params))}
  end

  def handle_event("copy_command", %{"command" => command}, socket) do
    {:noreply,
     socket
     |> push_event("copy-to-clipboard", %{text: command})
     |> put_flash(:info, "Copied command to clipboard.")}
  end

  def handle_event("export", params, socket) do
    project_root = socket.assigns.project_root
    target = params["target"]
    scope = params["scope"]

    result =
      case Skills.export(target, project_root, scope: scope) do
        {:ok, plan} ->
          {:info, "Exported #{plan.target} bundle to #{plan.output_dir}."}

        {:error, reason} ->
          {:error, "Failed to export skills: #{inspect(reason)}"}
      end

    {:noreply,
     socket
     |> put_flash(elem(result, 0), elem(result, 1))
     |> assign(:last_result, result)
     |> assign(:action_form, action_form(params))
     |> assign_analysis(project_root)}
  end

  def handle_event("install", params, socket) do
    project_root = socket.assigns.project_root
    target = params["target"]
    scope = params["scope"]

    result =
      case Skills.install(target, project_root, scope: scope) do
        {:ok, %{destination: destination} = install} ->
          agent_line =
            if Map.has_key?(install, :agent_destination) do
              " Agent: #{install.agent_destination}."
            else
              ""
            end

          {:info, "Installed #{install.target} skills to #{destination}.#{agent_line}"}

        {:ok, %ControlKeel.Skills.SkillExportPlan{} = plan} ->
          {:info, "Prepared #{plan.target} bundle at #{plan.output_dir}."}

        {:error, reason} ->
          {:error, "Failed to install skills: #{inspect(reason)}"}
      end

    {:noreply,
     socket
     |> put_flash(elem(result, 0), elem(result, 1))
     |> assign(:last_result, result)
     |> assign(:action_form, action_form(params))
     |> assign_analysis(project_root)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="w-[min(1180px,calc(100%-2rem))] mx-auto pt-8 pb-16">
        <div class="flex items-center justify-between gap-4 mt-6 mb-4">
          <div>
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Skills Studio</p>
            <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Native skills and plugin operator console</h1>
            <p class="text-[var(--ck-muted)] text-[1.05rem] leading-[1.7] max-w-[48rem]">
              ControlKeel keeps `priv/skills/` as the canonical source of truth, validates every skill package, and can export or install the same capability set for Codex, Claude Code, Cline, Copilot / VS Code, and MCP-only tools.
            </p>
          </div>
          <a href={~p"/"} class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Back home</a>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mb-4">
          <.form for={@project_form} id="skills-project-form" phx-submit="validate_project">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <.input
                  field={@project_form[:project_root]}
                  type="text"
                  label="Project root"
                  placeholder="/absolute/path/to/project"
                />
              </div>
              <div class="flex items-end">
                <button type="submit" class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full bg-[var(--ck-lime)] text-[#11170d] font-bold transition-[transform,box-shadow] duration-150 ease-in-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)] cursor-pointer" id="skills-project-submit">
                  Refresh catalog
                </button>
              </div>
            </div>
          </.form>
        </div>

        <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mt-5">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Total skills</p>
            <strong>{length(@skills)}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Skill warnings</p>
            <strong>{Enum.count(@diagnostics, &(&1.level == "warn"))}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Skill errors</p>
            <strong>{Enum.count(@diagnostics, &(&1.level == "error"))}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Local skills</p>
            <strong>{if @trusted_project?, do: "allowed", else: "gated"}</strong>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 my-4">
          <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Skill diagnostics</p>
          <div :if={@diagnostics == []} class="text-[var(--ck-muted)]">No skill diagnostics were recorded.</div>
          <div :if={@diagnostics != []} class="grid gap-4 m-0 p-0 list-none">
            <%= for diagnostic <- @diagnostics do %>
              <article class="border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)] grid gap-[0.55rem]">
                <div class="flex items-center justify-between gap-4">
                  <h3>{diagnostic.code}</h3>
                  <span class={"border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-[0.8rem] #{diagnostic_pill_class(diagnostic.level)}"}>
                    {diagnostic.level}
                  </span>
                </div>
                <p class="text-[var(--ck-muted)]">{diagnostic.message}</p>
                <p class="text-[var(--ck-muted)] mt-[0.35rem] font-mono">
                  {diagnostic.path}
                </p>
              </article>
            <% end %>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 my-4">
          <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Export and install</p>
          <.form for={@action_form} id="skills-action-form" phx-change="update_action_form">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <.input
                  field={@action_form[:target]}
                  type="select"
                  label="Target"
                  options={@target_options}
                />
              </div>
              <div>
                <.input
                  field={@action_form[:scope]}
                  type="select"
                  label="Scope"
                  options={@scope_options}
                />
              </div>
            </div>
            <div class="flex items-center justify-between gap-4 mt-4">
              <button
                type="button"
                class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full bg-[var(--ck-lime)] text-[#11170d] font-bold transition-[transform,box-shadow] duration-150 ease-in-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)] cursor-pointer"
                id="skills-export-button"
                phx-click="export"
                phx-value-target={@action_form.params["target"]}
                phx-value-scope={@action_form.params["scope"]}
              >
                Export bundle
              </button>
              <button
                type="button"
                class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full border border-[var(--ck-stroke)] bg-transparent text-[var(--ck-text)] font-semibold transition-[transform,background] duration-150 ease-in-out hover:bg-[var(--ck-panel)] hover:-translate-y-px cursor-pointer"
                id="skills-install-button"
                phx-click="install"
                phx-value-target={@action_form.params["target"]}
                phx-value-scope={@action_form.params["scope"]}
              >
                Install target
              </button>
            </div>
          </.form>
          <%= if @last_result do %>
            <p class="text-[var(--ck-muted)] mt-[0.85rem]">
              Last action: {elem(@last_result, 1)}
            </p>
          <% end %>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 my-4" id="skills-provider-status">
          <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Provider and bootstrap status</p>
          <div class="grid gap-4 m-0 p-0 list-none">
            <article class="border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)] grid gap-[0.55rem]">
              <div class="flex items-center justify-between gap-4">
                <h3>Active provider</h3>
                <span class="border border-[var(--ck-stroke)] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7] rounded-full px-3 py-[0.45rem] text-[0.8rem]">{@provider_status["selected_source"]}</span>
              </div>
              <p class="text-[var(--ck-muted)]">
                Provider: {@provider_status["selected_provider"]} / {@provider_status[
                  "selected_model"
                ] || "default"}
              </p>
              <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                Base URL: {selected_base_url(@provider_status)}
              </p>
              <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                Auth: {@provider_status["selected_auth_mode"]} / {@provider_status[
                  "selected_auth_owner"
                ]}
              </p>
              <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                Bootstrap mode: {@provider_status["bootstrap"]["mode"]}
              </p>
              <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                Fallback chain: {Enum.join(@provider_status["fallback_chain"], ", ")}
              </p>
            </article>
            <article class="border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)] grid gap-[0.55rem]" id="skills-registry-status">
              <div class="flex items-center justify-between gap-4">
                <h3>ACP registry cache</h3>
                <span class={[
                  "border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-[0.8rem]",
                  (@registry_status["stale"] && "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]") || "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
                ]}>
                  {if @registry_status["stale"], do: "stale", else: "fresh"}
                </span>
              </div>
              <p class="text-[var(--ck-muted)]">
                Entries: {@registry_status["entry_count"]} / matched integrations: {@registry_status[
                  "matched_integrations"
                ]}
              </p>
              <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                Fetched at: {@registry_status["fetched_at"] || "never"}
              </p>
            </article>
          </div>
        </div>

        <div class="grid grid-cols-[minmax(0,1.35fr)_minmax(280px,0.75fr)] gap-6 mt-6">
          <div class="space-y-4">
            <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
              <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Available skills</p>
              <div class="grid gap-4 m-0 p-0 list-none">
                <%= for skill <- @skills do %>
                  <article
                    id={"skill-#{skill.name}"}
                    class={[
                      "border border-[rgba(255,255,255,0.07)] rounded-[1.1rem] p-4 bg-[rgba(255,255,255,0.03)] grid gap-[0.55rem] cursor-pointer",
                      @selected && @selected.name == skill.name && "border-[var(--ck-lime)]"
                    ]}
                    phx-click="select_skill"
                    phx-value-name={skill.name}
                  >
                    <div class="flex items-center justify-between gap-4">
                      <h3>{skill.name}</h3>
                      <span class={"border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-[0.8rem] #{scope_pill_class(skill.scope)}"}>{skill.scope}</span>
                    </div>
                    <p class="text-[var(--ck-muted)]">{skill.description}</p>
                    <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                      Targets: {format_targets(skill.compatibility_targets)}
                    </p>
                  </article>
                <% end %>
              </div>
            </div>
          </div>

          <div class="space-y-4">
            <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
              <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Target availability</p>
              <div class="overflow-x-auto">
                <table class="min-w-full text-sm" id="skills-target-matrix">
                  <thead>
                    <tr>
                      <th class="text-left py-2 pr-4">Target</th>
                      <th class="text-left py-2 pr-4">Default scope</th>
                      <th class="text-left py-2 pr-4">Native</th>
                      <th class="text-left py-2 pr-4">Release asset</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for target <- @targets do %>
                      <tr id={"skill-target-#{target.id}"}>
                        <td class="py-2 pr-4">
                          <strong>{target.label}</strong>
                          <p class="text-[var(--ck-muted)]">{target.description}</p>
                        </td>
                        <td class="py-2 pr-4">{target.default_scope}</td>
                        <td class="py-2 pr-4">{if target.native, do: "yes", else: "fallback"}</td>
                        <td class="py-2 pr-4">
                          {if target.release_bundle, do: "published", else: "local only"}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
              <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">Available where</p>
              <div class="overflow-x-auto">
                <table class="min-w-full text-sm" id="skills-agent-matrix">
                  <thead>
                    <tr>
                      <th class="text-left py-2 pr-4">Agent</th>
                      <th class="text-left py-2 pr-4">How agent uses CK</th>
                      <th class="text-left py-2 pr-4">How CK runs the agent</th>
                      <th class="text-left py-2 pr-4">Companion and policy</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for integration <- @agent_integrations do %>
                      <tr id={"agent-#{integration.id}"}>
                        <td class="py-2 pr-4 align-top">
                          <strong>{integration.label}</strong>
                          <p class="text-[var(--ck-muted)]">{human_support_class(integration.support_class)}</p>
                        </td>
                        <td class="py-2 pr-4 align-top">
                          <p class="text-[var(--ck-muted)]">
                            Uses CK via: {format_targets(integration.agent_uses_ck_via)}
                          </p>
                          <%= if integration.attach_command do %>
                            <div class="flex items-start gap-2">
                              <code>{integration.attach_command}</code>
                              <button
                                type="button"
                                class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase"
                                id={"copy-agent-#{integration.id}"}
                                phx-click="copy_command"
                                phx-value-command={integration.attach_command}
                              >
                                Copy
                              </button>
                            </div>
                          <% else %>
                            <code>
                              {integration.runtime_export_command || alias_action(integration)}
                            </code>
                          <% end %>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Scope: {Enum.join(integration.supported_scopes, ", ")}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Install path: {human_install_experience(integration.install_experience)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Auto-bootstrap: {if integration.auto_bootstrap, do: "yes", else: "no"}
                          </p>
                        </td>
                        <td class="py-2 pr-4 align-top">
                          <p class="text-[var(--ck-muted)]">
                            CK runs via: {integration.ck_runs_agent_via || "none"}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Execution support: {integration.execution_support || "inbound_only"}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Review experience: {human_review_experience(integration.review_experience)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Submit / feedback: {integration.submission_mode} / {integration.feedback_mode}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Phase model / embed: {human_phase_model(integration.phase_model)} / {human_browser_embed(
                              integration.browser_embed
                            )}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Runtime / review transport: {integration.runtime_transport ||
                              "artifact_only"} / {integration.runtime_review_transport ||
                              "artifact_only"}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Subagent visibility: {human_subagent_visibility(
                              integration.subagent_visibility
                            )}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Autonomy: {integration.autonomy_mode || "policy_gated"}
                          </p>
                          <p class="text-[var(--ck-muted)]">{integration.config_location}</p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Required CK tools: {format_targets(integration.required_mcp_tools)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Auth: {integration.auth_mode} / {auth_owner(integration)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Provider bridge: {format_provider_bridge(integration.provider_bridge)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Runtime auth owner: {integration.runtime_auth_owner || "none"}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            MCP / skills: {integration.mcp_mode} / {integration.skills_mode}
                          </p>
                        </td>
                        <td class="py-2 pr-4 align-top">
                          <p class="text-[var(--ck-muted)]">{integration.companion_delivery}</p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Export targets: {format_targets(integration.export_targets)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Plan phases: {format_targets(integration.plan_phase_support)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Runtime sessions: {format_runtime_session_support(
                              integration.runtime_session_support
                            )}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Files written: {format_paths(integration.artifact_surfaces)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Package outputs: {format_package_outputs(integration.package_outputs)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Direct install: {format_direct_install_methods(
                              integration.direct_install_methods
                            )}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Human intervention: {human_intervention_copy(integration)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Confidence: {human_confidence_level(integration.confidence_level)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Upstream: {integration.upstream_slug || "n/a"}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            ACP registry: {registry_label(integration)}
                          </p>
                          <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                            Get CK: {format_install_channels(integration.install_channels)}
                          </p>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
              <%= if @selected do %>
                <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">{@selected.name}</p>
                <p class="text-[var(--ck-muted)] mb-3">{@selected.description}</p>
                <div class="flex flex-wrap gap-2 mb-3">
                  <%= for target <- @selected.compatibility_targets do %>
                    <span class="border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.05)] rounded-full px-3 py-[0.45rem] text-[0.8rem]">{target}</span>
                  <% end %>
                </div>
                <p class="text-[var(--ck-muted)] mb-2">
                  Required CK MCP tools: {format_targets(@selected.required_mcp_tools)}
                </p>
                <p class="text-[var(--ck-muted)] mb-2">
                  Native locations: {format_paths(
                    get_in(@selected.install_state, ["native_locations"])
                  )}
                </p>
                <p class="text-[var(--ck-muted)] mb-2">
                  Exported targets: {format_targets(
                    get_in(@selected.install_state, ["exported_targets"])
                  )}
                </p>
                <%= if @selected.resources != [] do %>
                  <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase mt-4">Resources</p>
                  <ul class="grid gap-4 m-0 p-0 list-none">
                    <%= for resource <- @selected.resources do %>
                      <li>{resource}</li>
                    <% end %>
                  </ul>
                <% end %>
                <%= if @selected.diagnostics != [] do %>
                  <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase mt-4">Skill diagnostics</p>
                  <ul class="grid gap-4 m-0 p-0 list-none">
                    <%= for diagnostic <- @selected.diagnostics do %>
                      <li>[{diagnostic.level}] {diagnostic.code} — {diagnostic.message}</li>
                    <% end %>
                  </ul>
                <% end %>
                <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase mt-4">Instructions preview</p>
                <pre class="text-[0.72rem] leading-[1.5] whitespace-pre-wrap break-words max-h-[420px] overflow-y-auto mt-2">{@selected.body}</pre>
              <% else %>
                <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">How this works</p>
                <ul class="grid gap-4 m-0 p-0 list-none">
                  <li>`priv/skills/` is the canonical built-in source of truth.</li>
                  <li>`ck_skill_list` and `ck_skill_load` remain the universal MCP fallback.</li>
                  <li>
                    Native targets are generated from the same catalog instead of being hand-maintained.
                  </li>
                  <li>
                    Project-local skills are only loaded when the project is trusted by ControlKeel.
                  </li>
                </ul>
              <% end %>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp assign_analysis(socket, project_root) do
    analysis = Skills.analyze(project_root)
    provider_status = ProviderBroker.status(project_root)
    registry_status = ACPRegistry.status()

    socket
    |> assign(:project_root, project_root)
    |> assign(:skills, analysis.skills)
    |> assign(:diagnostics, analysis.diagnostics)
    |> assign(:targets, Skills.targets())
    |> assign(:trusted_project?, analysis.trusted_project?)
    |> assign(:provider_status, provider_status)
    |> assign(:registry_status, registry_status)
  end

  defp project_form(project_root), do: to_form(%{"project_root" => project_root}, as: :project)

  defp action_form(params \\ %{"target" => "open-standard", "scope" => "export"}) do
    to_form(params, as: :skill_action)
  end

  defp target_options do
    Enum.map(Skills.targets(), fn target -> {target.label, target.id} end)
  end

  defp format_targets([]), do: "none"
  defp format_targets(nil), do: "none"
  defp format_targets(values), do: Enum.join(values, ", ")

  defp format_install_channels([]), do: "none"

  defp format_install_channels(ids) do
    ids
    |> ControlKeel.Distribution.install_channels()
    |> Enum.map(& &1.label)
    |> Enum.join(", ")
  end

  defp format_paths([]), do: "not installed"
  defp format_paths(nil), do: "not installed"
  defp format_paths(paths), do: Enum.join(paths, ", ")

  defp format_package_outputs([]), do: "none"
  defp format_package_outputs(nil), do: "none"

  defp format_package_outputs(outputs) do
    outputs
    |> Enum.map(fn output ->
      case output do
        %{"artifact" => artifact, "kind" => kind} -> "#{kind}: #{artifact}"
        %{artifact: artifact, kind: kind} -> "#{kind}: #{artifact}"
        other -> inspect(other)
      end
    end)
    |> Enum.join(", ")
  end

  defp format_direct_install_methods([]), do: "attach only"
  defp format_direct_install_methods(nil), do: "attach only"

  defp format_direct_install_methods(methods) do
    methods
    |> Enum.map(fn method ->
      case method do
        %{"label" => label, "command" => command} -> "#{label}: #{command}"
        %{label: label, command: command} -> "#{label}: #{command}"
        other -> inspect(other)
      end
    end)
    |> Enum.join(" | ")
  end

  defp format_runtime_session_support(nil), do: "none"
  defp format_runtime_session_support(%{} = support) when map_size(support) == 0, do: "none"

  defp format_runtime_session_support(%{} = support) do
    support
    |> Enum.filter(fn {_key, value} -> value end)
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> Enum.join(", ")
  end

  defp scope_pill_class("builtin"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp scope_pill_class("user"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp scope_pill_class("project"), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
  defp scope_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp diagnostic_pill_class("error"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp diagnostic_pill_class("warn"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp diagnostic_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp human_support_class("attach_client"), do: "Attachable client"
  defp human_support_class("headless_runtime"), do: "Headless runtime"
  defp human_support_class("framework_adapter"), do: "Framework adapter"
  defp human_support_class("provider_only"), do: "Provider-only"
  defp human_support_class("alias"), do: "Alias"
  defp human_support_class("unverified"), do: "Unverified"
  defp human_support_class(_), do: "Portable integration"

  defp human_install_experience("first_class"), do: "first-class"
  defp human_install_experience("guided"), do: "guided"
  defp human_install_experience("fallback"), do: "fallback"
  defp human_install_experience(_value), do: "guided"

  defp human_review_experience("native_review"), do: "native review"
  defp human_review_experience("browser_review"), do: "browser review"
  defp human_review_experience("feedback_only"), do: "feedback only"
  defp human_review_experience("none"), do: "none"
  defp human_review_experience(_value), do: "browser review"

  defp human_phase_model("host_plan_mode"), do: "host plan mode"
  defp human_phase_model("file_plan_mode"), do: "file plan mode"
  defp human_phase_model("review_only"), do: "review only"
  defp human_phase_model(_value), do: "review only"

  defp human_browser_embed("external"), do: "external browser"
  defp human_browser_embed("vscode_webview"), do: "VS Code webview"
  defp human_browser_embed("none"), do: "none"
  defp human_browser_embed(_value), do: "external browser"

  defp human_subagent_visibility("primary_only"), do: "primary only"
  defp human_subagent_visibility("all"), do: "all agents"
  defp human_subagent_visibility("none"), do: "none"
  defp human_subagent_visibility(_value), do: "none"

  defp human_confidence_level("shipped"), do: "shipped"
  defp human_confidence_level("experimental"), do: "experimental"
  defp human_confidence_level("research"), do: "research"
  defp human_confidence_level(_value), do: "shipped"

  defp alias_action(%{alias_of: alias_of}) when is_binary(alias_of), do: "Use #{alias_of}"
  defp alias_action(_integration), do: "reference only"

  defp auth_owner(integration), do: ControlKeel.AgentIntegration.auth_owner(integration)

  defp format_provider_bridge(%{supported: true, provider: provider, mode: mode}),
    do: "#{mode}: #{provider}"

  defp format_provider_bridge(%{supported: true, mode: mode}), do: mode
  defp format_provider_bridge(%{mode: "ck_owned"}), do: "ck-owned"
  defp format_provider_bridge(_bridge), do: "none"

  defp selected_base_url(%{"provider_chain" => [resolution | _]}) do
    resolution["base_url"] || "default"
  end

  defp selected_base_url(_status), do: "default"

  defp registry_label(%{registry_match: true, registry_version: version, registry_stale: stale}) do
    suffix = if stale, do: " (stale cache)", else: ""
    "matched #{version || "unknown"}#{suffix}"
  end

  defp registry_label(_integration), do: "not matched"

  defp human_intervention_copy(%{execution_support: "direct"}),
    do: "Only when findings or approvals block execution"

  defp human_intervention_copy(%{execution_support: "handoff"}),
    do: "Required to continue from the generated handoff package"

  defp human_intervention_copy(%{execution_support: "runtime"}),
    do: "Only when the remote runtime pauses or policy gates block"

  defp human_intervention_copy(_integration), do: "Use ControlKeel from the agent side only"
end
