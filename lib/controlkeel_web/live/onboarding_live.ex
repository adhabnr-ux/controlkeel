defmodule ControlKeelWeb.OnboardingLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Intent
  alias ControlKeel.Mission

  @impl true
  def mount(_params, _session, socket) do
    occupation = default_occupation()
    attrs = default_attrs(occupation)
    project_root = socket.endpoint.config(:project_root) || File.cwd!()

    {:ok,
     socket
     |> assign(:page_title, "Start a mission")
     |> assign(:project_root, project_root)
     |> assign(:occupation_profiles, Intent.occupation_profiles())
     |> assign(:agent_options, Intent.agent_options())
     |> assign(:step, 1)
     |> assign(:attrs, attrs)
     |> assign(:interview_questions, Intent.interview_questions(occupation))
     |> assign(:preflight, Intent.preflight_context(attrs))
     |> assign(:errors, %{})
     |> assign(:compile_error, nil)
     |> assign(:compiled_brief, nil)
     |> assign(:compiled_boundary_summary, Intent.boundary_summary(nil))
     |> assign(:started?, false)
     |> assign(:recent_sessions, Mission.list_recent_sessions())
     |> assign_form()}
  end

  @impl true
  def handle_event("validate", %{"launch" => params}, socket) do
    attrs = merge_launch_attrs(socket.assigns.attrs, params)

    {:noreply,
     socket
     |> assign(:attrs, attrs)
     |> assign(:interview_questions, Intent.interview_questions(attrs["occupation"]))
     |> assign(:preflight, Intent.preflight_context(attrs))
     |> assign(:compile_error, nil)
     |> assign_form()}
  end

  @impl true
  def handle_event("back", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, max(socket.assigns.step - 1, 1))
     |> assign(:errors, %{})
     |> assign(:compile_error, nil)}
  end

  @impl true
  def handle_event("next", %{"launch" => params}, socket) do
    attrs = merge_launch_attrs(socket.assigns.attrs, params)
    questions = Intent.interview_questions(attrs["occupation"])

    case validate_step(socket.assigns.step, attrs, questions) do
      {:ok, attrs} when socket.assigns.step < 3 ->
        socket =
          socket
          |> maybe_emit_interview_started(attrs)
          |> emit_interview_step_completed(attrs)
          |> assign(:attrs, attrs)
          |> assign(:interview_questions, questions)
          |> assign(:preflight, Intent.preflight_context(attrs))
          |> assign(:errors, %{})
          |> assign(:step, socket.assigns.step + 1)
          |> assign_form()

        {:noreply, socket}

      {:ok, attrs} ->
        socket =
          socket
          |> maybe_emit_interview_started(attrs)
          |> emit_interview_step_completed(attrs)
          |> assign(:attrs, attrs)
          |> assign(:interview_questions, questions)
          |> assign(:preflight, Intent.preflight_context(attrs))

        compile_brief(socket, attrs)

      {:error, errors} ->
        {:noreply,
         socket
         |> assign(:attrs, attrs)
         |> assign(:interview_questions, questions)
         |> assign(:preflight, Intent.preflight_context(attrs))
         |> assign(:errors, errors)
         |> assign_form()}
    end
  end

  @impl true
  def handle_event("regenerate", _params, socket) do
    compile_brief(socket, socket.assigns.attrs)
  end

  @impl true
  def handle_event("accept", _params, %{assigns: %{compiled_brief: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Compile the brief before creating a mission.")}
  end

  @impl true
  def handle_event("accept", _params, socket) do
    case Mission.create_launch_from_brief(socket.assigns.attrs, socket.assigns.compiled_brief) do
      {:ok, session} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/missions/#{session.id}?launched=1")}

      {:error, _scope, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "ControlKeel could not create the mission from this brief.")
         |> assign(:step, 4)}
    end
  end

  @impl true
  def handle_event("select_mission", params, socket) do
    id = params["id"] || params["recent_mission_id"]

    case id do
      "" ->
        {:noreply, socket}

      nil ->
        {:noreply, socket}

      id ->
        case Mission.get_session(String.to_integer(id)) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "Selected mission not found.")}

          session ->
            brief = session.execution_brief || %{}
            interview_answers = get_in(brief, ["compiler", "interview_answers"]) || %{}
            idea = Map.get(brief, "idea", session.objective)

            attrs =
              socket.assigns.attrs
              |> Map.merge(%{
                "project_name" => session.title,
                "idea" => idea,
                "interview_answers" => interview_answers
              })

            {:noreply,
             socket
             |> assign(:attrs, attrs)
             |> assign(:interview_questions, Intent.interview_questions(attrs["occupation"]))
             |> assign_form()}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <DashboardLayout.dashboard flash={@flash}>
      <section class="max-w-7xl mx-auto px-4 py-6">
        <div class="mb-8">
          <p class="text-xs font-semibold tracking-wider text-lime-400 uppercase font-mono">
            Mission onboarding
          </p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8 items-start">
          <div class="lg:col-span-2 rounded-2xl border border-zinc-800 bg-zinc-900/30 p-6 md:p-8 backdrop-blur-xl">
            <.form for={@form} phx-change="validate" phx-submit="next">
              <%= case @step do %>
                <% 1 -> %>
                  <div class="space-y-6">
                    <div>
                      <p class="text-xs font-semibold tracking-wider text-lime-400 uppercase font-mono">
                        Step 1 of 4
                      </p>
                      <h2 class="text-2xl font-serif text-zinc-100 mt-1">
                        Choose the domain and primary agent
                      </h2>
                    </div>

                    <div class="space-y-1.5">
                      <label class="text-xs font-semibold text-zinc-300 uppercase tracking-wider font-mono">
                        Domain profile
                      </label>
                      <select
                        name="launch[occupation]"
                        class="w-full bg-zinc-900/50 border border-zinc-800 hover:border-zinc-700 rounded-xl px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-1 focus:ring-lime-400 focus:border-lime-400 transition"
                      >
                        <%= for profile <- @occupation_profiles do %>
                          <option value={profile.id} selected={@attrs["occupation"] == profile.id}>
                            {profile.label}
                          </option>
                        <% end %>
                      </select>
                      <%= if error = field_error(@errors, "occupation") do %>
                        <p class="text-xs text-red-400 font-medium mt-1">{error}</p>
                      <% end %>
                    </div>

                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 pt-4 border-t border-zinc-800/60">
                      <div class="space-y-1.5">
                        <label class="text-xs font-semibold text-zinc-300 uppercase tracking-wider font-mono">
                          Primary agent
                        </label>
                        <select
                          name="launch[agent]"
                          class="w-full bg-zinc-900/50 border border-zinc-800 hover:border-zinc-700 rounded-xl px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-1 focus:ring-lime-400 focus:border-lime-400 transition"
                        >
                          <%= for {id, label} <- @agent_options do %>
                            <option value={id} selected={@attrs["agent"] == id}>{label}</option>
                          <% end %>
                        </select>
                        <%= if error = field_error(@errors, "agent") do %>
                          <p class="text-xs text-red-400 font-medium mt-1">{error}</p>
                        <% end %>
                      </div>

                      <div class="space-y-1.5">
                        <label class="text-xs font-semibold text-zinc-300 uppercase tracking-wider font-mono">
                          Daily budget (USD)
                        </label>
                        <input
                          type="number"
                          name="launch[budget]"
                          value={@attrs["budget"]}
                          min="0"
                          max="500"
                          step="5"
                          placeholder="30"
                          class="w-full bg-zinc-900/50 border border-zinc-800 hover:border-zinc-700 rounded-xl px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-1 focus:ring-lime-400 focus:border-lime-400 transition"
                        />
                        <%= if error = field_error(@errors, "budget") do %>
                          <p class="text-xs text-red-400 font-medium mt-1">{error}</p>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% 2 -> %>
                  <div class="space-y-6">
                    <div>
                      <p class="text-xs font-semibold tracking-wider text-lime-400 uppercase font-mono">
                        Step 2 of 4
                      </p>
                      <h2 class="text-2xl font-serif text-zinc-100 mt-1">
                        Describe the product
                      </h2>
                    </div>

                    <div class="space-y-4">
                      <div class="space-y-1.5">
                        <label class="text-xs font-semibold text-zinc-300 uppercase tracking-wider font-mono">
                          Project name
                        </label>
                        <input
                          type="text"
                          name="launch[project_name]"
                          value={@attrs["project_name"]}
                          placeholder="e.g., Clinic Intake Portal"
                          class="w-full bg-zinc-900/50 border border-zinc-800 hover:border-zinc-700 rounded-xl px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-1 focus:ring-lime-400 focus:border-lime-400 transition"
                        />
                        <%= if error = field_error(@errors, "project_name") do %>
                          <p class="text-xs text-red-400 font-medium mt-1">{error}</p>
                        <% end %>
                      </div>

                      <div class="space-y-1.5">
                        <label class="text-xs font-semibold text-zinc-300 uppercase tracking-wider font-mono">
                          Core product prompt
                        </label>
                        <textarea
                          name="launch[idea]"
                          rows="8"
                          placeholder="Describe what you want built in plain language."
                          class="w-full bg-zinc-900/50 border border-zinc-800 hover:border-zinc-700 rounded-xl px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-1 focus:ring-lime-400 focus:border-lime-400 transition"
                        ><%= @attrs["idea"] %></textarea>
                        <%= if error = field_error(@errors, "idea") do %>
                          <p class="text-xs text-red-400 font-medium mt-1">{error}</p>
                        <% end %>
                      </div>
                    </div>

                    <%= if @recent_sessions != [] do %>
                      <div class="border-t border-zinc-800/60 pt-6">
                        <div class="space-y-1.5">
                          <label class="text-xs font-semibold text-zinc-300 uppercase tracking-wider font-mono">
                            Or continue from an existing mission
                          </label>
                          <select
                            name="recent_mission_id"
                            class="w-full bg-zinc-900/50 border border-zinc-800 hover:border-zinc-700 rounded-xl px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-1 focus:ring-lime-400 focus:border-lime-400 transition"
                            phx-change="select_mission"
                          >
                            <option value="">Select a recent mission...</option>
                            <%= for session <- @recent_sessions do %>
                              <option value={session.id}>{session.title}</option>
                            <% end %>
                          </select>
                        </div>
                      </div>
                    <% end %>
                  </div>
                <% 3 -> %>
                  <div class="space-y-6">
                    <div>
                      <p class="text-xs font-semibold tracking-wider text-lime-400 uppercase font-mono">
                        Step 3 of 4
                      </p>
                      <h2 class="text-2xl font-serif text-zinc-100 mt-1">
                        Answer the guided interview
                      </h2>
                    </div>

                    <div class="space-y-6">
                      <%= for question <- @interview_questions do %>
                        <div class="space-y-1.5">
                          <label class="text-xs font-semibold text-zinc-300 uppercase tracking-wider font-mono">
                            {question.label}
                          </label>
                          <p class="text-xs text-zinc-400 leading-relaxed">{question.prompt}</p>
                          <textarea
                            name={"launch[interview_answers][#{question.id}]"}
                            rows="4"
                            placeholder={question.placeholder}
                            class="w-full bg-zinc-900/50 border border-zinc-800 hover:border-zinc-700 rounded-xl px-3 py-2 text-sm text-zinc-100 focus:outline-none focus:ring-1 focus:ring-lime-400 focus:border-lime-400 transition"
                          ><%= Map.get(@attrs["interview_answers"], question.id, "") %></textarea>
                          <%= if error = field_error(@errors, "interview_answers.#{question.id}") do %>
                            <p class="text-xs text-red-400 font-medium mt-1">{error}</p>
                          <% end %>
                        </div>
                      <% end %>
                      <%= if @compile_error do %>
                        <p class="text-sm text-yellow-450 font-medium bg-yellow-400/5 border border-yellow-400/20 rounded-xl p-4 mt-2">
                          {@compile_error}
                        </p>
                      <% end %>
                    </div>
                  </div>
                <% 4 -> %>
                  <div class="space-y-6">
                    <div>
                      <p class="text-xs font-semibold tracking-wider text-lime-400 uppercase font-mono">
                        Step 4 of 4
                      </p>
                      <h2 class="text-2xl font-serif text-zinc-100 mt-1">
                        Review the compiled brief
                      </h2>
                    </div>

                    <%= if @compiled_brief do %>
                      <% brief = Intent.to_brief_map(@compiled_brief) %>
                      <% compiler = brief["compiler"] || %{} %>

                      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 border-b border-zinc-805 pb-6">
                        <div>
                          <h4 class="text-xs font-semibold text-zinc-350 uppercase tracking-wider font-mono">
                            Objective
                          </h4>
                          <p class="text-zinc-400 text-sm mt-1 leading-relaxed">
                            {brief["objective"]}
                          </p>
                        </div>
                        <div>
                          <h4 class="text-xs font-semibold text-zinc-350 uppercase tracking-wider font-mono">
                            Project Name
                          </h4>
                          <p class="text-zinc-400 text-sm mt-1 leading-relaxed">
                            {@attrs["project_name"]}
                          </p>
                        </div>
                        <div class="md:col-span-2">
                          <h4 class="text-xs font-semibold text-zinc-350 uppercase tracking-wider font-mono">
                            Core Product Prompt
                          </h4>
                          <p class="text-zinc-400 text-sm mt-1 leading-relaxed">
                            {@attrs["idea"]}
                          </p>
                        </div>
                        <div>
                          <h4 class="text-xs font-semibold text-zinc-350 uppercase tracking-wider font-mono">
                            Next Step
                          </h4>
                          <p class="text-zinc-400 text-sm mt-1 leading-relaxed">
                            {brief["next_step"]}
                          </p>
                        </div>
                        <div>
                          <h4 class="text-xs font-semibold text-zinc-350 uppercase tracking-wider font-mono">
                            Compiler Info
                          </h4>
                          <p class="text-zinc-400 text-sm mt-1 leading-relaxed">
                            {compiler["provider"]} / {compiler["model"]}
                          </p>
                        </div>
                      </div>

                      <div class="grid grid-cols-1 md:grid-cols-2 gap-6 pt-2">
                        <div class="rounded-xl border border-zinc-800 bg-zinc-900/20 p-4">
                          <h4 class="text-xs font-semibold text-lime-400 uppercase tracking-wider font-mono mb-2">
                            Acceptance criteria
                          </h4>
                          <p class="text-xs text-zinc-400 leading-relaxed whitespace-pre-line">
                            {brief["acceptance_criteria"]}
                          </p>
                        </div>

                        <div class="rounded-xl border border-zinc-800 bg-zinc-900/20 p-4">
                          <h4 class="text-xs font-semibold text-lime-400 uppercase tracking-wider font-mono mb-2">
                            Production boundary
                          </h4>
                          <div class="space-y-3">
                            <div class="grid grid-cols-2 gap-2 text-xs">
                              <div>
                                <span class="text-zinc-500 block font-mono text-[10px] uppercase">
                                  Risk Tier
                                </span>
                                <span class="text-zinc-300 font-medium">
                                  {boundary_value(@compiled_boundary_summary, "risk_tier")}
                                </span>
                              </div>
                              <div>
                                <span class="text-zinc-500 block font-mono text-[10px] uppercase">
                                  Launch Window
                                </span>
                                <span class="text-zinc-300 font-medium">
                                  {boundary_value(@compiled_boundary_summary, "launch_window")}
                                </span>
                              </div>
                            </div>
                            <div>
                              <span class="text-zinc-500 text-xs block font-mono text-[10px] uppercase">
                                Budget Note
                              </span>
                              <span class="text-zinc-300 text-xs font-medium leading-relaxed">
                                {boundary_value(@compiled_boundary_summary, "budget_note")}
                              </span>
                            </div>
                            <div>
                              <span class="text-zinc-500 text-xs block mb-1 font-mono text-[10px] uppercase">
                                Constraints
                              </span>
                              <p class="text-xs text-zinc-400 leading-relaxed">
                                {boundary_text(@compiled_boundary_summary, "constraints")}
                              </p>
                            </div>
                          </div>
                        </div>

                        <div class="rounded-xl border border-zinc-800 bg-zinc-900/20 p-4 md:col-span-2">
                          <h4 class="text-xs font-semibold text-lime-400 uppercase tracking-wider font-mono mb-2">
                            Open Questions
                          </h4>
                          <ul class="text-xs text-zinc-400 space-y-1.5 list-disc list-inside">
                            <%= for item <- brief["open_questions"] || [] do %>
                              <li>{item}</li>
                            <% end %>
                          </ul>
                        </div>
                      </div>
                    <% else %>
                      <p class="text-zinc-400 text-sm">The brief is not available yet.</p>
                    <% end %>
                  </div>
              <% end %>

              <div class="flex items-center justify-between gap-4 mt-8 pt-4 border-t border-zinc-800/60">
                <%= if @step > 1 do %>
                  <button
                    class="px-4 py-2 text-xs font-semibold uppercase tracking-wider text-lime-400 hover:text-lime-300 transition font-mono"
                    type="button"
                    phx-click="back"
                  >
                    Back
                  </button>
                <% else %>
                  <div></div>
                <% end %>

                <button
                  :if={@step < 4}
                  class="px-6 py-2.5 rounded-full bg-lime-400 text-zinc-950 font-bold text-sm hover:bg-lime-300 hover:shadow-[0_0_20px_rgba(196,240,66,0.3)] transition-all duration-200"
                  type="submit"
                >
                  {if @step == 3, do: "Compile brief", else: "Continue"}
                </button>

                <div :if={@step == 4} class="flex flex-wrap items-center justify-between gap-4">
                  <button
                    class="px-6 py-2.5 rounded-full bg-zinc-800 text-zinc-400 font-semibold text-sm hover:bg-zinc-700 hover:text-zinc-200 transition-all duration-200"
                    phx-click="regenerate"
                  >
                    Regenerate
                  </button>
                  <button
                    class="px-6 py-2.5 rounded-full bg-lime-400 text-zinc-950 font-bold text-sm hover:bg-lime-300 hover:shadow-[0_0_20px_rgba(196,240,66,0.3)] transition-all duration-200"
                    type="button"
                    phx-click="accept"
                  >
                    Create mission
                  </button>
                </div>
              </div>
            </.form>
          </div>

          <div class="lg:col-span-1 space-y-6">
            <div class="rounded-2xl border border-zinc-800 bg-zinc-900/30 p-6 backdrop-blur-xl">
              <p class="text-[10px] font-semibold tracking-wider text-lime-400 uppercase font-mono mb-3">
                Domain pack preview
              </p>
              <div class="space-y-4">
                <div>
                  <h4 class="text-xs font-semibold text-zinc-400 font-mono uppercase tracking-wider">
                    Occupation
                  </h4>
                  <p class="text-zinc-200 text-sm mt-0.5">{@preflight.occupation.label}</p>
                </div>

                <div>
                  <h4 class="text-xs font-semibold text-zinc-400 font-mono uppercase tracking-wider">
                    Description
                  </h4>
                  <p class="text-zinc-200 text-sm mt-0.5">{@preflight.occupation.description}</p>
                </div>

                <div class="flex gap-2 justify-between">
                  <div>
                    <h4 class="text-xs font-semibold text-zinc-400 font-mono uppercase tracking-wider">
                      Domain
                    </h4>
                    <p class="text-zinc-200 text-sm mt-0.5">{@preflight.occupation.domain_pack}</p>
                  </div>

                  <div>
                    <h4 class="text-xs font-semibold text-zinc-400 font-mono uppercase tracking-wider">
                      preliminary risk
                    </h4>
                    <p class="text-zinc-200 text-sm mt-0.5">{@preflight.preliminary_risk_tier}</p>
                  </div>
                </div>

                <div>
                  <h4 class="text-xs font-semibold text-zinc-400 font-mono uppercase tracking-wider">
                    Validation emphasis
                  </h4>
                  <p class="text-zinc-200 text-sm mt-0.5 leading-relaxed">
                    {@preflight.validation_language}
                  </p>
                </div>
                <div>
                  <h4 class="text-xs font-semibold text-zinc-400 font-mono uppercase tracking-wider mb-1.5">
                    Compliance
                  </h4>
                  <div class="flex flex-wrap gap-1">
                    <%= for item <- @preflight.compliance do %>
                      <span class="px-2 py-0.5 rounded-md text-[10px] font-medium bg-zinc-800 text-zinc-300 border border-zinc-700/50">
                        {item}
                      </span>
                    <% end %>
                  </div>
                </div>
                <div>
                  <h4 class="text-xs font-semibold text-zinc-400 font-mono uppercase tracking-wider">
                    Stack guidance
                  </h4>
                  <p class="text-zinc-200 text-xs mt-0.5 leading-relaxed">
                    {@preflight.stack_guidance}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
    </DashboardLayout.dashboard>
    """
  end

  defp compile_brief(socket, attrs) do
    case Intent.compile(attrs) do
      {:ok, brief} ->
        {:noreply,
         socket
         |> assign(:attrs, attrs)
         |> assign(:errors, %{})
         |> assign(:compile_error, nil)
         |> assign(:compiled_brief, brief)
         |> assign(
           :compiled_boundary_summary,
           Intent.boundary_summary(brief)
         )
         |> assign(:step, 4)
         |> assign_form()}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:attrs, attrs)
         |> assign(:compile_error, compile_error_message(reason))
         |> assign(:errors, %{})
         |> assign_form()}
    end
  end

  defp assign_form(socket) do
    assign(socket, :form, to_form(socket.assigns.attrs, as: :launch))
  end

  defp boundary_value(map, key), do: Map.get(map, key) || "Not specified"

  defp boundary_text(map, key) do
    case Map.get(map, key, []) do
      items when is_list(items) and items != [] -> Enum.join(items, " ")
      "" <> rest -> rest
      _ -> "Not specified"
    end
  end

  defp validate_step(1, attrs, _questions) do
    errors =
      %{}
      |> maybe_error(
        "occupation",
        blank?(attrs["occupation"]),
        "Choose the occupation that best fits this mission."
      )
      |> maybe_error("agent", blank?(attrs["agent"]), "Choose the primary coding agent.")

    step_result(attrs, errors)
  end

  defp validate_step(2, attrs, _questions) do
    errors =
      %{}
      |> maybe_error(
        "project_name",
        blank?(attrs["project_name"]),
        "Give the project a name."
      )
      |> maybe_error(
        "project_name",
        duplicate_project_name?(attrs["project_name"]),
        "This project name is already used by an existing mission."
      )
      |> maybe_error(
        "idea",
        short_text?(attrs["idea"], 12),
        "Describe the product in a few concrete sentences (at least 12 characters)."
      )

    step_result(attrs, errors)
  end

  defp validate_step(3, attrs, questions) do
    errors =
      Enum.reduce(questions, %{}, fn question, acc ->
        answer = get_in(attrs, ["interview_answers", question.id])

        maybe_error(
          acc,
          "interview_answers.#{question.id}",
          short_text?(answer, 8),
          "Answer this question before compiling the brief (at least 8 characters)."
        )
      end)

    step_result(attrs, errors)
  end

  defp step_result(attrs, errors) when map_size(errors) == 0, do: {:ok, attrs}
  defp step_result(_attrs, errors), do: {:error, errors}

  defp maybe_error(errors, _field, false, _message), do: errors
  defp maybe_error(errors, field, true, message), do: Map.put(errors, field, message)

  defp maybe_emit_interview_started(%{assigns: %{started?: true}} = socket, _attrs), do: socket

  defp maybe_emit_interview_started(socket, attrs) do
    preflight = Intent.preflight_context(attrs)

    :telemetry.execute(
      [:controlkeel, :intent, :interview, :started],
      %{count: 1},
      %{
        occupation: attrs["occupation"],
        domain_pack: preflight.domain_pack,
        agent: attrs["agent"]
      }
    )

    assign(socket, :started?, true)
  end

  defp emit_interview_step_completed(socket, attrs) do
    preflight = Intent.preflight_context(attrs)

    :telemetry.execute(
      [:controlkeel, :intent, :interview, :step_completed],
      %{count: 1},
      %{
        step: socket.assigns.step,
        occupation: attrs["occupation"],
        domain_pack: preflight.domain_pack
      }
    )

    socket
  end

  defp merge_launch_attrs(current, incoming) do
    current_answers = Map.get(current, "interview_answers", %{})
    incoming_answers = Map.get(incoming, "interview_answers", %{})

    current
    |> Map.merge(stringify_map(incoming))
    |> Map.put("interview_answers", Map.merge(current_answers, stringify_map(incoming_answers)))
  end

  defp stringify_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp default_attrs(occupation) do
    %{
      "occupation" => occupation,
      "agent" => "claude",
      "budget" => "30",
      "project_name" => "",
      "idea" => "",
      "interview_answers" => %{}
    }
  end

  defp default_occupation do
    Intent.occupation_profiles()
    |> List.first()
    |> Map.fetch!(:id)
  end

  defp duplicate_project_name?(name) do
    not blank?(name) and Mission.project_name_taken?(name)
  end

  defp blank?(value), do: String.trim(to_string(value || "")) == ""

  defp short_text?(value, minimum),
    do: String.length(String.trim(to_string(value || ""))) < minimum

  defp field_error(errors, key), do: Map.get(errors, key)

  defp compile_error_message(reason) do
    "ControlKeel could not compile the execution brief yet (#{format_reason(reason)}). If you do not have a bridge, API key, or local Ollama model, ControlKeel still runs in heuristic mode for governance, proofs, skills, and benchmarks."
  end

  defp format_reason(%Ecto.Changeset{}), do: "schema validation failed"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
