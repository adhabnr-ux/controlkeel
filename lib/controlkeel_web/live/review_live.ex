defmodule ControlKeelWeb.ReviewLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Review")
     |> assign(:review, nil)
     |> assign(:diff_chunks, [])
     |> assign(:response_form, response_form())
     |> assign(:review_url, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, _uri, socket) do
    case parse_integer(id) do
      {:ok, review_id} ->
        case Mission.get_review_with_context(review_id) do
          nil ->
            {:noreply,
             socket
             |> put_flash(:error, "Review not found.")
             |> assign(:review, nil)
             |> assign(:diff_chunks, [])
             |> assign(:review_url, nil)}

          review ->
            {:noreply, assign_review(socket, review)}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid review id.")}
    end
  end

  @impl true
  def handle_event("respond", %{"review_response" => params}, socket) do
    review = socket.assigns.review

    annotations =
      case String.trim(params["annotation_text"] || "") do
        "" -> %{}
        text -> %{"browser_notes" => text}
      end

    case Mission.respond_review(review, %{
           "decision" => params["decision"],
           "feedback_notes" => params["feedback_notes"],
           "annotations" => annotations,
           "reviewed_by" => "browser"
         }) do
      {:ok, updated_review} ->
        {:noreply,
         socket
         |> assign_review(updated_review)
         |> put_flash(:info, "Review response saved.")}

      {:error, {:invalid_arguments, message}} ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Review not found.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to respond to review: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto w-[min(1180px,calc(100%-2rem))] pt-8 pb-16 max-[900px]:w-[min(100%-1.25rem,1180px)] max-[900px]:pt-6">
      <%= if @review do %>
        <div class="flex items-center justify-between gap-4 mt-6 mb-4 max-[900px]:flex-col max-[900px]:items-start">
          <div>
            <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
              Browser Review
            </p>
            <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">{@review.title}</h1>
            <p class="text-muted-foreground text-[1.05rem] leading-[1.7] max-w-[48rem]">
              Review type: {String.capitalize(@review.review_type)}. Task: {if @review.task,
                do: @review.task.title,
                else: "session-level submission"}.
            </p>
          </div>
          <a
            class="uppercase tracking-[0.14em] text-xs text-primary font-semibold"
            href={~p"/missions/#{@review.session_id}"}
          >
            Open mission
          </a>
        </div>

        <div class="grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-4 mt-5">
          <div
            class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
            id="review-status-card"
          >
            <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
              Status
            </p>
            <strong>{String.capitalize(@review.status)}</strong>
          </div>
          <div class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
              Phase
            </p>
            <strong>{review_phase(@review)}</strong>
          </div>
          <div class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
              Submitted by
            </p>
            <strong>{@review.submitted_by || "agent"}</strong>
          </div>
          <div class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6">
            <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
              Shareable URL
            </p>
            <a
              class="uppercase tracking-[0.14em] text-xs text-primary font-semibold"
              href={@review_url}
            >
              {@review_url}
            </a>
          </div>
        </div>

        <div
          class="grid grid-cols-[minmax(0,1.35fr)_minmax(280px,0.75fr)] gap-6 max-[900px]:grid-cols-1 mt-6"
          style="margin-top: 1rem;"
        >
          <div class="space-y-4">
            <article
              class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
              id="review-submission-body"
            >
              <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                Submission
              </p>
              <pre class="m-0 p-4 border border-border rounded-xl bg-white/[0.03] text-foreground whitespace-pre-wrap break-words font-mono text-[0.9rem] leading-[1.6]">{@review.submission_body}</pre>
            </article>

            <article
              :if={
                present_plan_context?(@review, "alignment_context") or
                  present_plan_context?(@review, "consulted_roles")
              }
              class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
              id="review-alignment-card"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                    Alignment context
                  </p>
                  <h2>Human context gathered before execution</h2>
                </div>
              </div>
              <div class="mt-4 space-y-4">
                <div :if={present_plan_context?(@review, "alignment_context")}>
                  <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                    Context that shaped the plan
                  </p>
                  <ul class="list-disc space-y-2 pl-5 text-sm text-slate-700">
                    <li :for={entry <- plan_context(@review, "alignment_context")}>{entry}</li>
                  </ul>
                </div>
                <div :if={present_plan_context?(@review, "consulted_roles")}>
                  <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                    Roles consulted
                  </p>
                  <div class="flex flex-wrap gap-2">
                    <span
                      :for={role <- plan_context(@review, "consulted_roles")}
                      class="border border-border bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"
                    >
                      {role}
                    </span>
                  </div>
                </div>
              </div>
            </article>

            <article
              :if={present_semantic_boundaries?(@review)}
              class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
              id="review-semantic-boundaries-card"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                    Semantic boundaries
                  </p>
                  <h2>Agent execution guardrails</h2>
                </div>
              </div>
              <div class="mt-4 space-y-4">
                <div :for={boundary <- semantic_boundary_sections(@review)}>
                  <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                    {boundary.label}
                  </p>
                  <ul class="list-disc space-y-2 pl-5 text-sm text-slate-700">
                    <li :for={entry <- boundary.entries}>{entry}</li>
                  </ul>
                </div>
              </div>
            </article>

            <article
              :if={@review.previous_review}
              class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
              id="review-diff-card"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                    Revision diff
                  </p>
                  <h2>Compared with review #{@review.previous_review_id}</h2>
                </div>
                <span class="border border-border bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
                  Previous: {String.capitalize(@review.previous_review.status)}
                </span>
              </div>
              <div class="mt-4 space-y-3">
                <%= for chunk <- @diff_chunks do %>
                  <div class={diff_chunk_class(chunk.kind)}>
                    <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                      {diff_chunk_label(chunk.kind)}
                    </p>
                    <pre class="m-0 p-4 border border-border rounded-xl bg-white/[0.03] text-foreground whitespace-pre-wrap break-words font-mono text-[0.9rem] leading-[1.6]">{chunk.text}</pre>
                  </div>
                <% end %>
              </div>
            </article>
          </div>

          <div class="space-y-4">
            <article
              class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
              id="review-response-card"
            >
              <div class="flex items-center justify-between gap-4">
                <div>
                  <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                    Respond
                  </p>
                  <h2>Approve, deny, or annotate</h2>
                </div>
                <span class={review_status_pill_class(@review.status)}>
                  {String.capitalize(@review.status)}
                </span>
              </div>

              <.form for={@response_form} id="review-response-form" phx-submit="respond">
                <div class="space-y-4">
                  <.input
                    field={@response_form[:decision]}
                    type="select"
                    label="Decision"
                    options={[{"Approve", "approved"}, {"Deny", "denied"}]}
                  />

                  <.input
                    field={@response_form[:feedback_notes]}
                    type="textarea"
                    label="Feedback notes"
                    rows="6"
                  />

                  <.input
                    field={@response_form[:annotation_text]}
                    type="textarea"
                    label="Annotations"
                    rows="5"
                  />

                  <button
                    class="inline-flex items-center justify-center gap-[0.4rem] px-[1.25rem] py-[0.95rem] rounded-full bg-primary text-[#11170d] font-bold transition-[transform,box-shadow] duration-[160ms] ease-out hover:-translate-y-px hover:shadow-[0_12px_24px_rgba(196,240,66,0.24)]"
                    id="review-response-submit"
                    type="submit"
                  >
                    Save response
                  </button>
                </div>
              </.form>
            </article>

            <article
              class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
              id="review-audit-card"
            >
              <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
                Audit trail
              </p>
              <div class="grid gap-4 m-0 p-0 list-none">
                <article class="grid gap-[0.55rem] border border-white/[0.07] rounded-[1.1rem] p-4 bg-white/[0.03]">
                  <div class="flex items-center justify-between gap-4">
                    <h3>Submitted</h3>
                    <span class="border border-border bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]">
                      {format_dt(@review.inserted_at)}
                    </span>
                  </div>
                  <p class="text-muted-foreground">By {@review.submitted_by || "agent"}</p>
                </article>
                <article
                  :if={@review.responded_at}
                  class="grid gap-[0.55rem] border border-white/[0.07] rounded-[1.1rem] p-4 bg-white/[0.03]"
                >
                  <div class="flex items-center justify-between gap-4">
                    <h3>Responded</h3>
                    <span class={review_status_pill_class(@review.status)}>
                      {String.capitalize(@review.status)}
                    </span>
                  </div>
                  <p class="text-muted-foreground">At {format_dt(@review.responded_at)}</p>
                  <p class="text-muted-foreground">By {@review.reviewed_by || "human"}</p>
                  <p :if={present?(@review.feedback_notes)} class="text-muted-foreground">
                    {@review.feedback_notes}
                  </p>
                </article>
              </div>
            </article>
          </div>
        </div>
      <% else %>
        <div
          class="border border-border bg-card rounded-3xl backdrop-blur-[18px] shadow-[0_24px_80px_rgba(0,0,0,0.22)] p-6"
          id="review-missing"
        >
          <p class="uppercase tracking-[0.14em] text-xs text-primary font-semibold">
            Browser Review
          </p>
          <h1 class="text-[clamp(2rem,4vw,3.4rem)] leading-[1.02]">Review not found</h1>
        </div>
      <% end %>
    </section>
    """
  end

  defp assign_review(socket, review) do
    socket
    |> assign(:review, review)
    |> assign(:page_title, review.title)
    |> assign(:review_url, ControlKeelWeb.Endpoint.url() <> "/reviews/#{review.id}")
    |> assign(:diff_chunks, diff_chunks(review))
    |> assign(:response_form, response_form(review))
  end

  defp response_form(review \\ nil) do
    to_form(
      %{
        "decision" => default_decision(review),
        "feedback_notes" => (review && review.feedback_notes) || "",
        "annotation_text" => annotation_text(review)
      },
      as: :review_response
    )
  end

  defp default_decision(nil), do: "approved"
  defp default_decision(review) when review.status in ["approved", "denied"], do: review.status
  defp default_decision(_review), do: "approved"

  defp annotation_text(nil), do: ""

  defp annotation_text(review) do
    review.annotations
    |> Kernel.||(%{})
    |> case do
      %{"browser_notes" => notes} -> notes
      _ -> ""
    end
  end

  defp diff_chunks(%{previous_review: nil}), do: []

  defp diff_chunks(review) do
    previous_lines = String.split(review.previous_review.submission_body || "", "\n")
    current_lines = String.split(review.submission_body || "", "\n")

    previous_lines
    |> List.myers_difference(current_lines)
    |> Enum.map(fn
      {:eq, lines} -> %{kind: :unchanged, text: Enum.join(lines, "\n")}
      {:ins, lines} -> %{kind: :added, text: Enum.join(lines, "\n")}
      {:del, lines} -> %{kind: :removed, text: Enum.join(lines, "\n")}
    end)
    |> Enum.reject(&(String.trim(&1.text) == ""))
  end

  defp diff_chunk_class(:added),
    do: "rounded-2xl border border-emerald-200 bg-emerald-50/80 p-4"

  defp diff_chunk_class(:removed),
    do: "rounded-2xl border border-rose-200 bg-rose-50/80 p-4"

  defp diff_chunk_class(:unchanged),
    do: "rounded-2xl border border-slate-200 bg-slate-50/80 p-4"

  defp diff_chunk_label(:added), do: "Added"
  defp diff_chunk_label(:removed), do: "Removed"
  defp diff_chunk_label(:unchanged), do: "Unchanged"

  defp review_status_pill_class("approved"),
    do:
      "border border-border bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp review_status_pill_class("denied"),
    do:
      "border border-border bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,143,107,0.12)] text-[#ffd6cb]"

  defp review_status_pill_class("superseded"),
    do:
      "border border-border bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(255,207,107,0.12)] text-[#fff0bf]"

  defp review_status_pill_class(_status),
    do:
      "border border-border bg-white/5 rounded-full px-[0.8rem] py-[0.45rem] text-[0.8rem] bg-[rgba(125,226,174,0.1)] text-[#d2ffe7]"

  defp review_phase(review) do
    review
    |> Map.get(:task)
    |> case do
      nil -> "review"
      task -> Mission.review_gate_status(task)["phase"]
    end
  end

  defp format_dt(nil), do: "pending"
  defp format_dt(value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M UTC")

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp plan_context(review, key) do
    get_in(review.metadata || %{}, ["plan_refinement", key]) || []
  end

  defp present_plan_context?(review, key) do
    plan_context(review, key) != []
  end

  defp present_semantic_boundaries?(review) do
    semantic_boundary_sections(review) != []
  end

  defp semantic_boundary_sections(review) do
    [
      {"Allowed semantic changes", "allowed_semantic_changes"},
      {"Forbidden semantic changes", "forbidden_semantic_changes"},
      {"Invariant boundaries", "invariant_boundaries"},
      {"Requires re-approval if", "requires_reapproval_if"},
      {"Harness quality checks", "harness_quality_checks"}
    ]
    |> Enum.map(fn {label, key} -> %{label: label, entries: plan_context(review, key)} end)
    |> Enum.reject(&(&1.entries == []))
  end

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end
end
