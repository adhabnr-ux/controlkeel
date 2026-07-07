defmodule ControlKeel.Governance.RollbackExecutor do
  @moduledoc """
  Makes rollback executable, not just advisory.

  Records a git checkpoint before each task and provides a single action
  to revert an agent's work. Safety-checked: refuses if downstream tasks
  depend on the changes.
  """

  import Ecto.Query, warn: false

  alias ControlKeel.Repo
  alias ControlKeel.Mission.{Finding, RollbackSnapshot, Task}

  @doc """
  Capture the current git HEAD as a checkpoint before a task starts.
  Returns {:ok, snapshot} or {:error, reason}.
  """
  def checkpoint(session_id, task_id, opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    with {:ok, commit_sha} <- git_head_sha(project_root) do
      attrs = %{
        session_id: session_id,
        task_id: task_id,
        commit_sha_before: commit_sha,
        status: "available",
        rollback_method: Keyword.get(opts, :rollback_method, "git_revert"),
        metadata: %{}
      }

      %RollbackSnapshot{}
      |> RollbackSnapshot.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Execute a rollback for a task. Returns {:ok, snapshot} or {:error, reason}.

  Safety checks:
  - Snapshot must be "available"
  - No downstream completed tasks can depend on this task's changes
  - Creates an audit finding on every rollback
  """
  def execute(session_id, task_id, opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    reason = Keyword.get(opts, :reason, "Operator-initiated rollback")
    rolled_back_by = Keyword.get(opts, :rolled_back_by, "operator")

    snapshot =
      RollbackSnapshot
      |> where([s], s.session_id == ^session_id and s.task_id == ^task_id)
      |> order_by(desc: :id)
      |> limit(1)
      |> Repo.one()

    case snapshot do
      nil ->
        {:error, :no_snapshot}

      %{status: "rolled_back"} ->
        {:error, :already_rolled_back}

      %{status: status} when status in ["expired", "unsafe"] ->
        {:error, {:unsafe, "Snapshot status is #{status}"}}

      %{status: "available"} ->
        with :ok <- safety_check(session_id, task_id, snapshot) do
          case do_git_rollback(snapshot, project_root) do
            {:ok, revert_sha} ->
              {:ok, finding} =
                create_rollback_finding(session_id, task_id, reason, rolled_back_by)

              snapshot
              |> RollbackSnapshot.changeset(%{
                status: "rolled_back",
                rolled_back_at: DateTime.utc_now(),
                rolled_back_by: rolled_back_by,
                finding_id: finding.id,
                metadata: Map.put(snapshot.metadata, "revert_sha", revert_sha)
              })
              |> Repo.update()

            {:error, git_error} ->
              {:error, {:git_error, git_error}}
          end
        end
    end
  end

  @doc "Get the rollback snapshot status for a task."
  def status(session_id, task_id) do
    RollbackSnapshot
    |> where([s], s.session_id == ^session_id and s.task_id == ^task_id)
    |> order_by(desc: :id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "List all rollback snapshots for a session."
  def list(session_id) do
    RollbackSnapshot
    |> where([s], s.session_id == ^session_id)
    |> order_by(desc: :id)
    |> Repo.all()
  end

  defp safety_check(session_id, task_id, _snapshot) do
    downstream_tasks =
      Task
      |> where([t], t.session_id == ^session_id and t.id > ^task_id)
      |> where([t], t.status == "completed")
      |> Repo.all()

    if downstream_tasks == [] do
      :ok
    else
      {:error,
       {:unsafe,
        "Cannot rollback: #{length(downstream_tasks)} completed task(s) started after this one. " <>
          "Rollback would break their assumptions."}}
    end
  end

  defp do_git_rollback(snapshot, project_root) do
    before_sha = snapshot.commit_sha_before
    after_sha = snapshot.commit_sha_after || "HEAD"

    case snapshot.rollback_method do
      "git_revert" ->
        case ControlKeel.Git.cmd(["revert", "--no-commit", "#{before_sha}..#{after_sha}"],
               cd: project_root,
               stderr_to_stdout: true
             ) do
          {_, 0} ->
            case ControlKeel.Git.cmd(["commit", "-m", "ck_rollback: task #{snapshot.task_id}"],
                   cd: project_root,
                   stderr_to_stdout: true
                 ) do
              {_, 0} -> git_head_sha(project_root)
              {error, _} -> {:error, error}
            end

          {error, _} ->
            {:error, error}
        end

      "git_reset" ->
        case ControlKeel.Git.cmd(["reset", "--hard", before_sha],
               cd: project_root,
               stderr_to_stdout: true
             ) do
          {_, 0} -> {:ok, before_sha}
          {error, _} -> {:error, error}
        end

      "manual" ->
        {:ok, "manual"}
    end
  end

  defp git_head_sha(project_root) do
    case ControlKeel.Git.cmd(["rev-parse", "HEAD"], cd: project_root, stderr_to_stdout: true) do
      {sha, 0} -> {:ok, String.trim(sha)}
      {error, _} -> {:error, error}
    end
  end

  defp create_rollback_finding(session_id, task_id, reason, rolled_back_by) do
    %Finding{}
    |> Finding.changeset(%{
      session_id: session_id,
      title: "Task rolled back",
      severity: "medium",
      category: "governance",
      rule_id: "CK-ROLLBACK-001",
      plain_message: "Task #{task_id} rolled back by #{rolled_back_by}. Reason: #{reason}",
      status: "open",
      auto_resolved: false,
      metadata: %{"task_id" => task_id, "rolled_back_by" => rolled_back_by}
    })
    |> Repo.insert()
  end
end
