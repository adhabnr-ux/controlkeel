defmodule ControlKeel.MCP.Tools.CkWorktreeSwitch do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission
  alias ControlKeel.Project.WorkspaceContext

  def call(arguments) when is_map(arguments) do
    with {:ok, session} <- Arguments.fetch_session(arguments),
         {:ok, worktree_path} <- validate_worktree_path(arguments),
         {:ok, project_root} <- get_project_root(session, arguments),
         {:ok, worktrees_info} <- WorkspaceContext.list_worktrees(project_root),
         {:ok, target_worktree} <- find_worktree(worktrees_info["worktrees"], worktree_path) do
      updated_metadata =
        Map.put(session.metadata || %{}, "worktree_path", target_worktree["path"])

      case Mission.update_session(session, %{metadata: updated_metadata}) do
        {:ok, _updated_session} ->
          {:ok,
           %{
             "message" => "Switched to worktree at #{target_worktree["path"]}",
             "worktree" => target_worktree,
             "session_id" => session.id
           }}

        {:error, reason} ->
          {:error, {:invalid_arguments, "Failed to update session metadata: #{inspect(reason)}"}}
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp validate_worktree_path(arguments) do
    case Map.get(arguments, "worktree_path") do
      nil -> {:error, {:invalid_arguments, "`worktree_path` is required"}}
      path when is_binary(path) and path != "" -> {:ok, Path.expand(path)}
      _ -> {:error, {:invalid_arguments, "`worktree_path` must be a string"}}
    end
  end

  defp get_project_root(session, arguments) do
    case Map.get(session.metadata, "runtime_context", %{}) do
      %{"project_root" => root} when is_binary(root) and root != "" ->
        {:ok, Path.expand(root)}

      _ ->
        case Map.get(session.metadata, "project_root") do
          root when is_binary(root) and root != "" -> {:ok, Path.expand(root)}
          _ -> {:ok, Arguments.project_root(arguments)}
        end
    end
  end

  defp find_worktree(worktrees, target_path) do
    normalized_target = Path.expand(target_path)

    case Enum.find(worktrees, fn worktree ->
           Path.expand(worktree["path"]) == normalized_target
         end) do
      nil -> {:error, {:invalid_arguments, "Worktree not found at #{target_path}"}}
      worktree -> {:ok, worktree}
    end
  end
end
