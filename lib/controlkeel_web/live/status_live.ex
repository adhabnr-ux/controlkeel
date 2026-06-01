defmodule ControlKeelWeb.StatusLive do
  @moduledoc """
  Public status page at `/status`.

  Shows system health checks (DB, PubSub) and a placeholder for
  incident history. No auth required.
  """

  use ControlKeelWeb, :live_view

  alias ControlKeel.Repo

  @impl true
  def mount(_params, _session, socket) do
    checks = run_checks()

    {:ok,
     socket
     |> assign(:page_title, "Status — ControlKeel")
     |> assign(:checks, checks)
     |> assign(:overall, overall_status(checks))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="ck-shell" style="max-width: 640px; margin: 4rem auto;">
        <div class="flex items-center gap-3 mb-8">
          <div class={
            classes([
              "size-4 rounded-full",
              if(@overall == :healthy, do: "bg-emerald-400", else: "bg-amber-400")
            ])
          }>
          </div>
          <h1 class="text-3xl font-bold text-white">
            {if @overall == :healthy, do: "All systems operational", else: "Partial degradation"}
          </h1>
        </div>

        <div class="space-y-3 mb-12">
          <%= for {name, status, latency_ms} <- @checks do %>
            <div class="flex items-center justify-between rounded-lg border border-white/10 bg-zinc-900 px-4 py-3">
              <div class="flex items-center gap-3">
                <div class={
                  classes([
                    "size-3 rounded-full",
                    case status do
                      :ok -> "bg-emerald-400"
                      :error -> "bg-red-400"
                      :degraded -> "bg-amber-400"
                    end
                  ])
                }>
                </div>
                <span class="text-sm font-medium text-white">{name}</span>
              </div>
              <span class="text-xs text-zinc-500">
                {case status do
                  :ok -> "#{latency_ms}ms"
                  :error -> "unavailable"
                  :degraded -> "degraded"
                end}
              </span>
            </div>
          <% end %>
        </div>

        <div class="mb-8">
          <h2 class="text-lg font-semibold text-white mb-4">Incident history</h2>
          <p class="text-sm text-zinc-500">No incidents recorded.</p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp run_checks do
    [
      check_database(),
      check_pubsub()
    ]
  end

  defp check_database do
    start = System.monotonic_time(:millisecond)

    try do
      case Repo.query("SELECT 1") do
        {:ok, _} ->
          latency = System.monotonic_time(:millisecond) - start
          {"Database", :ok, latency}

        {:error, _} ->
          {"Database", :error, nil}
      end
    rescue
      _ -> {"Database", :error, nil}
    end
  end

  defp check_pubsub do
    start = System.monotonic_time(:millisecond)

    try do
      :ok = Phoenix.PubSub.subscribe(ControlKeel.PubSub, "__status_check__")
      Phoenix.PubSub.unsubscribe(ControlKeel.PubSub, "__status_check__")
      latency = System.monotonic_time(:millisecond) - start
      {"PubSub", :ok, latency}
    rescue
      _ -> {"PubSub", :error, nil}
    end
  end

  defp overall_status(checks) do
    if Enum.all?(checks, fn {_, status, _} -> status == :ok end) do
      :healthy
    else
      :degraded
    end
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
