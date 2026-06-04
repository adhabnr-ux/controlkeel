defmodule ControlKeelWeb.SkillsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Skills

  @impl true
  def mount(_params, _session, socket) do
    project_root = File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Skills Studio")
     |> assign(:selected, nil)
     |> assign(:last_result, nil)
     |> assign(:target_options, target_options())
     |> assign(:scope_options, [{"Export", "export"}, {"User", "user"}, {"Project", "project"}])
     |> assign_analysis(project_root)
     |> assign(:project_form, project_form(project_root))
     |> assign(:action_form, action_form())
     |> assign(:skill_search, "")
     |> assign(:target_search, "")}
  end

  @impl true
  def handle_event("select_skill", %{"name" => name}, socket) do
    selected = Enum.find(socket.assigns.skills, &(&1.name == name))
    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("search_skills", %{"skill_search" => search}, socket) do
    skills = socket.assigns.skills
    like = String.downcase(String.trim(search))

    filtered =
      if like == "" do
        skills
      else
        Enum.filter(skills, fn skill ->
          String.contains?(String.downcase(skill.name), like) or
            (skill.description && String.contains?(String.downcase(skill.description), like))
        end)
      end

    {:noreply,
     socket
     |> assign(:skill_search, search)
     |> assign(:filtered_skills, filtered)}
  end

  def handle_event("search_targets", %{"target_search" => search}, socket) do
    targets = socket.assigns.targets
    like = String.downcase(String.trim(search))

    filtered =
      if like == "" do
        targets
      else
        Enum.filter(targets, fn target ->
          String.contains?(String.downcase(target.label), like) or
            (target.description && String.contains?(String.downcase(target.description), like))
        end)
      end

    {:noreply,
     socket
     |> assign(:target_search, search)
     |> assign(:filtered_targets, filtered)}
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
        <div class="mb-6 space-y-1">
          <h2 class="text-2xl font-semibold text-[var(--ck-lime)] leading-6 tracking-wide uppercase">
            Skills Studio
          </h2>
          <p class="text-[var(--ck-muted)]">
            Native skills and plugin operator console
          </p>
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
                  class="p-3 w-full focus:outline-[var(--ck-stroke)] border-r-1 border-[var(--ck-stroke)]"
                />
              </div>
              <div class="flex items-end">
                <button
                  type="submit"
                  class="inline-flex items-center justify-center gap-[0.4rem] px-5 py-[0.95rem] rounded-full bg-[var(--ck-lime)] text-[#11170d] font-bold transition-[transform,box-shadow] duration-150 ease-in-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)] cursor-pointer"
                  id="skills-project-submit"
                >
                  Refresh catalog
                </button>
              </div>
            </div>
          </.form>
        </div>

        <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mt-5">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
              Total skills
            </p>
            <strong>{length(@skills)}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
              Skill warnings
            </p>
            <strong>{Enum.count(@diagnostics, &(&1.level == "warn"))}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
              Skill errors
            </p>
            <strong>{Enum.count(@diagnostics, &(&1.level == "error"))}</strong>
          </div>
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
              Local skills
            </p>
            <strong>{if @trusted_project?, do: "allowed", else: "gated"}</strong>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 my-4">
          <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
            Skill diagnostics
          </p>
          <div :if={@diagnostics == []} class="text-[var(--ck-muted)]">
            No skill diagnostics were recorded.
          </div>
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
          <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
            Export and install
          </p>
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

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
          <%= if @selected do %>
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
              {@selected.name}
            </p>
            <p class="text-[var(--ck-muted)] mb-3">{@selected.description}</p>
            <div class="flex flex-wrap gap-2 mb-3">
              <%= for target <- @selected.compatibility_targets do %>
                <span class="border border-[var(--ck-stroke)] bg-[rgba(255,255,255,0.05)] rounded-full px-3 py-[0.45rem] text-[0.8rem]">
                  {target}
                </span>
              <% end %>
            </div>
            <p class="text-[var(--ck-muted)] mb-2">
              Required CK MCP tools: {format_targets(@selected.required_mcp_tools)}
            </p>
            <p class="text-[var(--ck-muted)] mb-2">
              Native locations: {format_paths(get_in(@selected.install_state, ["native_locations"]))}
            </p>
            <p class="text-[var(--ck-muted)] mb-2">
              Exported targets: {format_targets(get_in(@selected.install_state, ["exported_targets"]))}
            </p>
            <%= if @selected.resources != [] do %>
              <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase mt-4">
                Resources
              </p>
              <ul class="grid gap-4 m-0 p-0 list-none">
                <%= for resource <- @selected.resources do %>
                  <li>{resource}</li>
                <% end %>
              </ul>
            <% end %>
            <%= if @selected.diagnostics != [] do %>
              <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase mt-4">
                Skill diagnostics
              </p>
              <ul class="grid gap-4 m-0 p-0 list-none">
                <%= for diagnostic <- @selected.diagnostics do %>
                  <li>[{diagnostic.level}] {diagnostic.code} — {diagnostic.message}</li>
                <% end %>
              </ul>
            <% end %>
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase mt-4">
              Instructions preview
            </p>
            <pre class="text-[0.72rem] leading-[1.5] whitespace-pre-wrap break-words max-h-[420px] overflow-y-auto mt-2">{@selected.body}</pre>
          <% else %>
            <p class="text-xs font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
              How this works
            </p>
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
            <p class="text-[var(--ck-muted)] text-sm leading-[1.7] mt-4">
              ControlKeel keeps `priv/skills/` as the canonical source of truth, validates every skill package, and can export or install the same capability set for Codex, Claude Code, Cline, Copilot / VS Code, and MCP-only tools.
            </p>
          <% end %>
        </div>

        <div class="space-y-4 mt-10">
          <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="text-lg font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
              Available skills
            </p>

            <form phx-change="search_skills">
              <input
                type="text"
                name="skill_search"
                value={@skill_search}
                placeholder="Filter skills by name or description..."
                phx-debounce="150"
                class="mt-3 mb-4 p-3 w-full bg-[rgba(255,255,255,0.04)] border border-[var(--ck-stroke)] rounded-xl text-[var(--ck-text)] outline-none focus:border-[var(--ck-lime)] transition-colors duration-150"
              />
            </form>

            <div
              id="skills-list"
              class="grid gap-4 m-0 p-0 list-none overflow-y-auto max-h-[500px] pr-2"
              style="scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.15) transparent;"
            >
              <%= for skill <- @filtered_skills do %>
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
                    <span class={"border border-[var(--ck-stroke)] rounded-full px-3 py-[0.45rem] text-[0.8rem] #{scope_pill_class(skill.scope)}"}>
                      {skill.scope}
                    </span>
                  </div>
                  <p class="text-[var(--ck-muted)]">{skill.description}</p>
                  <p class="text-[var(--ck-muted)] mt-[0.35rem]">
                    Targets: {format_targets(skill.compatibility_targets)}
                  </p>
                </article>
              <% end %>
            </div>
            <style>
              #skills-list::-webkit-scrollbar { width: 6px; }
              #skills-list::-webkit-scrollbar-track { background: transparent; }
              #skills-list::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
              #skills-list::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }
            </style>
          </div>
        </div>

        <div class="border border-[var(--ck-stroke)] bg-[var(--ck-panel)] rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6 mt-10">
          <p class="text-lg font-semibold text-[var(--ck-lime)] tracking-[0.14em] uppercase">
            Target availability
          </p>

          <form phx-change="search_targets">
            <input
              type="text"
              name="target_search"
              value={@target_search}
              placeholder="Filter targets by name or description..."
              phx-debounce="150"
              class="mt-3 mb-4 p-3 w-full bg-[rgba(255,255,255,0.04)] border border-[var(--ck-stroke)] rounded-xl text-[var(--ck-text)] outline-none focus:border-[var(--ck-lime)] transition-colors duration-150"
            />
          </form>

          <div
            id="targets-list"
            class="overflow-y-auto max-h-[500px] pr-2"
            style="scrollbar-width: thin; scrollbar-color: rgba(255,255,255,0.15) transparent;"
          >
            <table class="min-w-full text-sm" id="skills-target-matrix">
              <thead>
                <tr class="sticky top-0">
                  <th class="text-left py-2 pr-4">Target</th>
                  <th class="text-left py-2 pr-4">Default scope</th>
                  <th class="text-left py-2 pr-4">Native</th>
                  <th class="text-left py-2 pr-4">Release asset</th>
                </tr>
              </thead>
              <tbody>
                <%= for target <- @filtered_targets do %>
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
          <style>
            #targets-list::-webkit-scrollbar { width: 6px; }
            #targets-list::-webkit-scrollbar-track { background: transparent; }
            #targets-list::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
            #targets-list::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }
          </style>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp assign_analysis(socket, project_root) do
    analysis = Skills.analyze(project_root)

    socket
    |> assign(:project_root, project_root)
    |> assign(:skills, analysis.skills)
    |> assign(:filtered_skills, analysis.skills)
    |> assign(:diagnostics, analysis.diagnostics)
    |> assign(:targets, Skills.targets())
    |> assign(:filtered_targets, Skills.targets())
    |> assign(:trusted_project?, analysis.trusted_project?)
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

  defp format_paths([]), do: "not installed"
  defp format_paths(nil), do: "not installed"
  defp format_paths(paths), do: Enum.join(paths, ", ")

  defp scope_pill_class("builtin"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp scope_pill_class("user"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp scope_pill_class("project"), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
  defp scope_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp diagnostic_pill_class("error"), do: "bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"
  defp diagnostic_pill_class("warn"), do: "bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"
  defp diagnostic_pill_class(_), do: "bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
end
