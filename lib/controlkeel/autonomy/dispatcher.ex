defmodule ControlKeel.Autonomy.Dispatcher do
  @moduledoc """
  Default dispatch for a fired autonomy job: produces a governed wake-up.

  A wake-up is a session + task + `autonomy.wake` audit event committed in one
  database transaction. Only after that invariant exists may an external launcher
  run; its result is recorded as a separate `autonomy.launch.result` event.

  The wake-up is what makes the autonomy heartbeat governed: the next agent run
  (whether launched here or picked up later) starts inside a real CK session with
  a task, an audit trail, and recoverable memory — never as an orphan process.
  """

  require Logger

  alias ControlKeel.Autonomy.Job
  alias ControlKeel.Autonomy.Launcher.Shell
  alias ControlKeel.Mission
  alias ControlKeel.Mission.SessionTranscript
  alias ControlKeel.Mission.Workspace
  alias ControlKeel.Repo

  @wake_event_type "autonomy.wake"
  @launch_result_event_type "autonomy.launch.result"
  @default_budget_cents 5_000
  @default_risk_tier "medium"

  @doc """
  Dispatch `job`.

  Options:

  * `:workspace_id` — required workspace to bind the wake-up session to.
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

  defp fire(%Job{} = job, workspace_id, opts) do
    with {:ok, %{session: session, task: task}} <- persist_wake_up(job, workspace_id),
         launched <- maybe_launch(job, opts),
         :ok <- record_launch_result(session, job, task, launched) do
      {:ok,
       %{
         session_id: session.id,
         task_id: task.id,
         launched: launched,
         workspace_id: workspace_id
       }}
    end
  end

  defp persist_wake_up(job, workspace_id) do
    case Repo.transaction(fn ->
           with {:ok, session} <- create_session(job, workspace_id),
                {:ok, task} <- create_task(job, session),
                {:ok, _event} <- record_wake_event(session, job, task) do
             %{session: session, task: task}
           else
             {:error, reason} -> Repo.rollback(reason)
           end
         end) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, {:wake_persistence_failed, reason}}
    end
  rescue
    error -> {:error, {:wake_persistence_failed, Exception.message(error)}}
  catch
    kind, reason -> {:error, {:wake_persistence_failed, {kind, inspect(reason)}}}
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
  defp maybe_launch(%Job{launcher: nil}, _opts), do: nil

  defp maybe_launch(%Job{} = job, opts) do
    case Shell.run(job, opts) do
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

        %{error: inspect(reason)}
    end
  end

  defp record_wake_event(session, job, task) do
    payload = %{
      job: to_string(job.name),
      task_id: task.id,
      agent: job.agent,
      launcher: job.launcher != nil,
      phase: "prepared"
    }

    SessionTranscript.record(%{
      session_id: session.id,
      task_id: task.id,
      event_type: @wake_event_type,
      actor: "autonomy.scheduler",
      summary: "Autonomy wake-up prepared: " <> job.title,
      payload: payload
    })
  end

  defp record_launch_result(_session, %Job{launcher: nil}, _task, nil), do: :ok

  defp record_launch_result(session, job, task, launched) do
    case SessionTranscript.record(%{
           session_id: session.id,
           task_id: task.id,
           event_type: @launch_result_event_type,
           actor: "autonomy.scheduler",
           summary: "Autonomy launcher result: " <> job.title,
           payload: format_launched(launched)
         }) do
      {:ok, _event} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "[autonomy] launch completed but result audit failed for #{inspect(job.name)}: #{inspect(reason)}"
        )

        {:error, {:launch_result_audit_failed, reason}}
    end
  end

  defp format_launched(nil), do: %{"status" => "skipped"}

  defp format_launched(%{error: error}) do
    %{"status" => "failed", "error" => to_string(error)}
  end

  defp format_launched(%{exit_status: status, output: output}) do
    %{"status" => "completed", "exit_status" => status, "output" => output}
  end

  defp resolve_workspace(opts) do
    case opts[:workspace_id] do
      id when is_integer(id) and id > 0 ->
        if Repo.get(Workspace, id), do: {:ok, id}, else: {:error, :workspace_not_found}

      _ ->
        {:error, :workspace_id_required}
    end
  end
end
