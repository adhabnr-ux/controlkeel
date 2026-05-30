defmodule ControlKeel.Governance.ExternalServiceTracker do
  @moduledoc """
  Tracks and governs agent interactions with external SaaS APIs.

  Rate limits per service, cost attribution, and audit trail.
  Inspired by: "Agents will create massive new demand for SaaS."
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Repo
  alias ControlKeel.Mission.ExternalServiceInteraction

  @default_rate_limit_per_service 60
  @default_rate_limit_total 200
  @rate_window_seconds 60

  @doc "Record an external service interaction."
  def record(attrs) when is_map(attrs) do
    %ExternalServiceInteraction{}
    |> ExternalServiceInteraction.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get aggregated summary for a session."
  def summary(session_id) do
    interactions =
      ExternalServiceInteraction
      |> where([i], i.session_id == ^session_id)
      |> Repo.all()

    total_calls = length(interactions)
    total_cost = Enum.sum(Enum.map(interactions, & &1.cost_cents))

    error_count =
      Enum.count(interactions, fn i -> i.status_code != nil and i.status_code >= 400 end)

    by_service =
      interactions
      |> Enum.group_by(& &1.service_name)
      |> Enum.map(fn {service, items} ->
        %{
          service_name: service,
          calls: length(items),
          cost_cents: Enum.sum(Enum.map(items, & &1.cost_cents)),
          error_rate:
            if(length(items) > 0,
              do:
                Float.round(
                  Enum.count(items, fn i -> i.status_code != nil and i.status_code >= 400 end) /
                    length(items) * 100,
                  1
                ),
              else: 0.0
            ),
          avg_latency_ms: avg_latency(items)
        }
      end)
      |> Enum.sort_by(& &1.calls, :desc)

    %{
      total_calls: total_calls,
      total_cost_cents: total_cost,
      error_rate:
        if(total_calls > 0, do: Float.round(error_count / total_calls * 100, 1), else: 0.0),
      services: by_service
    }
  end

  @doc "Check rate limit status for a session."
  def rate_limit_status(session_id) do
    cutoff = DateTime.add(DateTime.utc_now(), -@rate_window_seconds, :second)

    recent =
      ExternalServiceInteraction
      |> where([i], i.session_id == ^session_id and i.inserted_at >= ^cutoff)
      |> Repo.all()

    by_service =
      recent
      |> Enum.group_by(& &1.service_name)
      |> Enum.map(fn {service, items} ->
        %{
          service_name: service,
          calls: length(items),
          limit: @default_rate_limit_per_service,
          remaining: max(@default_rate_limit_per_service - length(items), 0),
          exceeded: length(items) >= @default_rate_limit_per_service
        }
      end)

    total = length(recent)

    %{
      total_calls: total,
      total_limit: @default_rate_limit_total,
      total_remaining: max(@default_rate_limit_total - total, 0),
      total_exceeded: total >= @default_rate_limit_total,
      per_service: by_service
    }
  end

  @doc "Get top services by call volume and cost."
  def top_services(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    ExternalServiceInteraction
    |> where([i], i.session_id == ^session_id)
    |> group_by([i], i.service_name)
    |> select([i], %{
      service_name: i.service_name,
      call_count: count(i.id),
      total_cost_cents: sum(i.cost_cents),
      avg_latency_ms: avg(i.latency_ms)
    })
    |> order_by([i], desc: count(i.id))
    |> limit(^limit)
    |> Repo.all()
  end

  defp avg_latency(items) do
    latencies = Enum.filter(items, &(&1.latency_ms != nil)) |> Enum.map(& &1.latency_ms)

    if latencies == [] do
      nil
    else
      Float.round(Enum.sum(latencies) / length(latencies), 1)
    end
  end
end
