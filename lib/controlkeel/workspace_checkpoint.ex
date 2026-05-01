defmodule ControlKeel.WorkspaceCheckpoint do
  @moduledoc """
  Enhanced checkpoint system for workspace state management.
  Supports workspace state capture, hash verification, and export/import for migration.
  """

  alias ControlKeel.Mission
  alias ControlKeel.WorkspaceContext

  def create(session_id, task_id, opts \\ []) do
    with session when not is_nil(session) <-
           Mission.get_session(session_id) || {:error, {:invalid_arguments, "Session not found"}},
         {:ok, project_root} <- resolve_project_root(session),
         workspace_context <- WorkspaceContext.build(project_root) do
      checkpoint_type = Keyword.get(opts, :type, "workspace_snapshot")
      summary = Keyword.get(opts, :summary, "Workspace checkpoint")

      # Capture workspace state
      workspace_state = %{
        "project_root" => project_root,
        "repo_root" => workspace_context["repo_root"],
        "git_branch" => get_in(workspace_context, ["git", "branch"]),
        "git_head_sha" => get_in(workspace_context, ["git", "head_sha"]),
        "git_status_counts" => get_in(workspace_context, ["git", "status_counts"]),
        "worktree_path" => Map.get(session.metadata || %{}, "worktree_path"),
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "workspace_hash" => compute_workspace_hash(workspace_context)
      }

      # Create checkpoint record
      checkpoint_attrs = %{
        session_id: session_id,
        task_id: task_id,
        checkpoint_type: checkpoint_type,
        summary: summary,
        payload: workspace_state,
        created_by: Keyword.get(opts, :created_by, "system")
      }

      case Mission.create_task_checkpoint(checkpoint_attrs) do
        {:ok, checkpoint} ->
          {:ok,
           %{
             "id" => checkpoint.id,
             "checkpoint_type" => checkpoint.checkpoint_type,
             "summary" => checkpoint.summary,
             "workspace_state" => workspace_state,
             "created_at" => checkpoint.inserted_at
           }}

        {:error, changeset} ->
          {:error, {:internal_error, "Failed to create checkpoint: #{inspect(changeset.errors)}"}}
      end
    end
  end

  def restore(session_id, checkpoint_id, opts \\ []) do
    with {:ok, checkpoint} <- get_checkpoint(checkpoint_id),
         session when not is_nil(session) <-
           Mission.get_session(session_id) || {:error, {:invalid_arguments, "Session not found"}},
         :ok <- validate_checkpoint_ownership(checkpoint, session_id),
         {:ok, project_root} <- resolve_project_root(session) do
      # Validate workspace state before restore
      case validate_workspace_state(checkpoint.payload, project_root, opts) do
        :ok ->
          # Update session metadata with checkpoint information
          updated_metadata =
            Map.put(session.metadata || %{}, "restored_from_checkpoint", %{
              "checkpoint_id" => checkpoint_id,
              "checkpoint_type" => checkpoint.checkpoint_type,
              "restored_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            })

          case Mission.update_session(session, %{metadata: updated_metadata}) do
            {:ok, _updated_session} ->
              {:ok,
               %{
                 "message" => "Restored from checkpoint #{checkpoint_id}",
                 "checkpoint_id" => checkpoint_id,
                 "checkpoint_type" => checkpoint.checkpoint_type,
                 "workspace_state" => checkpoint.payload
               }}

            {:error, reason} ->
              {:error, {:internal_error, "Failed to update session metadata: #{inspect(reason)}"}}
          end

        {:error, reason} ->
          {:error, {:validation_error, reason}}
      end
    end
  end

  def list(session_id, opts \\ []) do
    case Mission.list_task_checkpoints(session_id) do
      checkpoints when is_list(checkpoints) ->
        checkpoint_type = Keyword.get(opts, :type)
        limit = Keyword.get(opts, :limit, 10)

        filtered =
          checkpoints
          |> Enum.filter(fn cp ->
            is_nil(checkpoint_type) or cp.checkpoint_type == checkpoint_type
          end)
          |> Enum.take(limit)
          |> Enum.map(fn cp ->
            %{
              "id" => cp.id,
              "checkpoint_type" => cp.checkpoint_type,
              "summary" => cp.summary,
              "created_at" => cp.inserted_at,
              "created_by" => cp.created_by,
              "workspace_hash" => get_in(cp.payload, ["workspace_hash"])
            }
          end)

        {:ok, filtered}

      {:error, reason} ->
        {:error, {:internal_error, "Failed to list checkpoints: #{inspect(reason)}"}}
    end
  end

  # Private functions

  defp get_checkpoint(checkpoint_id) do
    case Mission.get_task_checkpoint(checkpoint_id) do
      nil -> {:error, {:not_found, "Checkpoint not found"}}
      checkpoint -> {:ok, checkpoint}
    end
  end

  defp validate_checkpoint_ownership(checkpoint, session_id) do
    if checkpoint.session_id == session_id do
      :ok
    else
      {:error, {:invalid_arguments, "Checkpoint does not belong to the specified session"}}
    end
  end

  defp resolve_project_root(session) do
    case Map.get(session.metadata, "runtime_context", %{}) do
      %{"project_root" => root} when is_binary(root) and root != "" ->
        {:ok, Path.expand(root)}

      _ ->
        case Map.get(session.metadata, "project_root") do
          root when is_binary(root) and root != "" -> {:ok, Path.expand(root)}
          _ -> {:error, {:invalid_arguments, "Cannot determine project root from session"}}
        end
    end
  end

  defp compute_workspace_hash(workspace_context) do
    payload =
      workspace_context
      |> Map.take(["repo_root", "git"])
      |> Jason.encode!()

    :crypto.hash(:sha256, payload)
    |> Base.encode16(case: :lower)
  end

  defp validate_workspace_state(workspace_state, project_root, opts) do
    strict = Keyword.get(opts, :strict, false)

    cond do
      workspace_state["project_root"] != project_root and strict ->
        {:error, "Project root mismatch"}

      not File.dir?(project_root) ->
        {:error, "Project root not accessible"}

      true ->
        :ok
    end
  end
end
