defmodule ControlKeelWeb.SessionReviewsLive do
  use ControlKeelWeb, :live_view

  alias ControlKeel.Mission

  @refresh_interval_ms 2_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns[:current_org_id]

    case Mission.get_session_context(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Session not found.")
         |> push_navigate(to: ~p"/")}

      session when not is_nil(org_id) and not is_nil(session) ->
        if session_accessible?(session, org_id) do
          {:ok, mount_session(socket, session)}
        else
          {:ok,
           socket
           |> put_flash(:error, "Session not found.")
           |> push_navigate(to: ~p"/")}
        end

      session ->
        {:ok, mount_session(socket, session)}
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: schedule_refresh()
    {:noreply, assign_reviews(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mx-auto max-w-[1180px] w-full px-4 pt-8 pb-16">
      <div class="mb-8">
        <div class="flex flex-wrap items-start justify-between gap-4">
          <div class="space-y-1">
            <h2 class="text-2xl font-semibold text-primary leading-6 tracking-wide uppercase">
              Review queue
            </h2>
            <p class="text-muted-foreground">
              Plan, diff, and completion submissions for {@session.title}.
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-5 max-w-lg">
          <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Total
            </p>
            <strong>{@review_counts.total} total</strong>
          </div>
          <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Pending
            </p>
            <strong>{@review_counts.pending} pending</strong>
          </div>
          <div class="p-5 rounded-3xl border bg-card/70 backdrop-blur-xl shadow-lg">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-primary mb-1">
              Resolved
            </p>
            <strong>{resolved_count(@reviews)} resolved</strong>
          </div>
        </div>
      </div>

      <div class="bg-card border rounded-2xl shadow-card overflow-clip">
        <table class="min-w-full divide-y divide-border text-left text-sm">
          <thead class="bg-muted text-xs uppercase tracking-[0.14em] text-muted-foreground">
            <tr>
              <th class="px-5 py-3 font-semibold">Review</th>
              <th class="px-5 py-3 font-semibold">Task</th>
              <th class="px-5 py-3 font-semibold">Type</th>
              <th class="px-5 py-3 font-semibold">Submitted by</th>
              <th class="px-5 py-3 font-semibold">Date</th>
              <th class="px-5 py-3 font-semibold text-right">Status</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <%= for review <- @reviews do %>
              <tr class="transition hover:bg-muted/30">
                <td class="px-5 py-4">
                  <.link
                    navigate={~p"/sessions/#{@session.id}/reviews/#{review.id}"}
                    class="font-medium text-foreground hover:text-primary"
                  >
                    {review.title}
                  </.link>
                </td>
                <td class="px-5 py-4 text-muted-foreground">
                  {if review.task, do: review.task.title, else: "Session-level"}
                </td>
                <td class="px-5 py-4 text-muted-foreground capitalize">{review.review_type}</td>
                <td class="px-5 py-4 text-muted-foreground">{review.submitted_by || "agent"}</td>
                <td class="px-5 py-4 text-muted-foreground whitespace-nowrap font-mono tabular-nums tracking-tight">
                  {event_timestamp(review.inserted_at)}
                </td>
                <td class="px-5 py-4 text-right">
                  <span class={review_status_pill_class(review.status)}>{review.status}</span>
                </td>
              </tr>
            <% end %>
            <%= if @reviews == [] do %>
              <tr>
                <td colspan="6" class="px-5 py-12 text-center">
                  <p class="text-base font-medium text-foreground">No reviews yet.</p>
                  <p class="mt-1 text-sm text-muted-foreground">
                    Agent plan, diff, or completion submissions for this session appear here.
                  </p>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp mount_session(socket, session) do
    if connected?(socket), do: schedule_refresh()

    socket
    |> assign(:page_title, "#{session.title} — Reviews")
    |> assign(:session, session)
    |> assign_reviews()
  end

  defp assign_reviews(socket) do
    session_id = socket.assigns.session.id

    socket
    |> assign(:reviews, Mission.list_reviews_for_session(session_id))
    |> assign(:review_counts, Mission.session_review_counts(session_id))
  end

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval_ms)

  defp resolved_count(reviews) do
    Enum.count(reviews, &(&1.status in ["approved", "denied", "superseded"]))
  end

  defp event_timestamp(nil), do: "unknown"

  defp event_timestamp(%DateTime{} = timestamp),
    do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")

  defp review_status_pill_class("approved"),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-success/10 text-success ring-success/20"

  defp review_status_pill_class("denied"),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-destructive/10 text-destructive ring-destructive/20"

  defp review_status_pill_class("superseded"),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-warning/10 text-warning ring-warning/20"

  defp review_status_pill_class(_status),
    do:
      "inline-flex rounded-full px-2.5 py-1 text-xs font-semibold capitalize ring-1 bg-info/10 text-info ring-info/20"

  defp session_accessible?(%{workspace_id: ws_id}, org_id) when is_integer(org_id) do
    org_id
    |> ControlKeel.Accounts.list_workspaces_for_org()
    |> Enum.any?(fn ws -> ws.id == ws_id end)
  end
end
