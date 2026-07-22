defmodule ControlKeel.Autonomy.Dispatcher do
  @moduledoc """
  Default dispatch for a fired autonomy job: produces a governed wake-up.

  A wake-up is a session + task + `autonomy.wake` audit event. When the job has a
  launcher configured AND shell launching is enabled, the dispatcher also invokes
  the launcher and records its result in the same event.

  The wake-up is what makes the autonomy heartbeat governed: the next agent run
  (whether launched here or picked up later) starts inside a real CK session with
  a task, an audit trail, and recoverable memory — never as an orphan process.
  """

  require Logger

  alias ControlKeel.Accounts
  alias ControlKeel.Autonomy.Job
  alias ControlKeel.Autonomy.Launcher.Shell
  alias ControlKeel.Mission
  alias ControlKeel.Mission.SessionTranscript

  @wake_event_type "autonomy.wake"
  @default_budget_cents 5_000
  @default_risk_tier "medium"

  @doc """
  Dispatch `job`.

  Options:

  * `:workspace_id` — workspace to bind the wake-up session to. When omitted, the
    first workspace of the first org is used (autonomous runs need a home).
  * `:dry_run` — when `true`, validates and returns the plan without recording
    anything or launching anything.

  Returns `{:ok, %{session_id, task_id, launched}}` or `{:error, reason}`.
  """
  def dispatch(job, opts \\ [])

  def dispatch(%Job{} = job, opts) do
    with {:ok, workspace_id} <- resolve_workspace(opts) do
      if opts[:dry_run] do
        {:ok, %{dry_run: true, job: job.name, workspace_id: workspace_id, launched: false}}
      else
        fire(job, workspace_id, opts)
      end
    end
  end

  defp fire(%Job{} = job, workspace_id, _opts) do
    {:ok, session} = create_session(job, workspace_id)
    {:ok, task} = create_task(job, session)
    launched = maybe_launch(job)

    :ok = record_wake_event(session, job, task, launched)

    {:ok,
     %{session_id: session.id, task_id: task.id, launched: launched, workspace_id: workspace_id}}
  end

  defp create_session(%Job{} = job, workspace_id) do
    Mission.create_session(%{
      title: "[autonomy] " <> job.title,
      objective: job.task,
      risk_tier: @default_risk_tier,
      status: "in_progress",
      budget_cents: @default_budget_cents,
      daily_budget_cents: @default_budget_cents,
      spent_cents: 0,
      execution_brief: %{"source" => "autonomy.scheduler", "job" => to_string(job.name)},
      workspace_id: workspace_id
    })
  end

  defp create_task(%Job{} = job, session) do
    Mission.create_task(%{
      session_id: session.id,
      title: job.title,
      status: "pending",
      estimated_cost_cents: 0,
      validation_gate: "manual",
      position: 0,
      metadata: %{"source" => "autonomy", "job" => to_string(job.name)}
    })
  end

  # A job with a launcher launches when shell execution is enabled. Otherwise the
  # wake-up is recorded and an external launcher (or a later run) picks it up.
  defp maybe_launch(%Job{launcher: nil}), do: nil

  defp maybe_launch(%Job{} = job) do
    case Shell.run(job, []) do
      {:ok, result} ->
        result

      {:error, :shell_not_allowed} ->
        Logger.warning(
          "[autonomy] job #{inspect(job.name)} has a launcher but shell execution is disabled; wake-up recorded without launch"
        )

        nil

      {:error, reason} ->
        Logger.warning(
          "[autonomy] launcher for job #{inspect(job.name)} failed: #{inspect(reason)}"
        )

        %{error: reason}
    end
  end

  defp record_wake_event(session, job, task, launched) do
    payload = %{
      job: to_string(job.name),
      task_id: task.id,
      agent: to_string(job.agent),
      launcher: job.launcher != nil,
      launched: format_launched(launched)
    }

    {:ok, _event} =
      SessionTranscript.record(%{
        session_id: session.id,
        event_type: @wake_event_type,
        actor: "autonomy.scheduler",
        summary: "Autonomy wake-up: " <> job.title,
        payload: payload
      })

    :ok
  end

  defp format_launched(nil), do: false
  defp format_launched(%{error: _} = err), do: err
  defp format_launched(result), do: Map.take(result, [:exit_status])

  defp resolve_workspace(opts) do
    case opts[:workspace_id] do
      id when is_integer(id) and id > 0 ->
        {:ok, id}

      _ ->
        default_workspace_id()
    end
  end

  # Autonomous runs need a workspace. When none is configured, fall back to the
  # first workspace of the first org so a freshly-enabled scheduler can run.
  defp default_workspace_id do
    case Accounts.list_orgs() do
      [org | _] ->
        case Accounts.list_workspaces_for_org(org.id) do
          [ws | _] -> {:ok, ws.id}
          [] -> {:error, :no_workspace_configured}
        end

      [] ->
        {:error, :no_workspace_configured}
    end
  end
end
