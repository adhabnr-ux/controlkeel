defmodule ControlKeel.MCP.Tools.CkTask do
  @moduledoc false

  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission
  alias ControlKeel.Platform

  @allowed_modes ~w(status claim complete heartbeat checks report)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments),
         {:ok, result} <- dispatch(normalized) do
      {:ok, result}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, task_id} <- Arguments.optional_integer(arguments, "task_id"),
         {:ok, mode} <- mode(arguments) do
      {:ok,
       %{
         "session_id" => session_id,
         "task_id" => task_id,
         "mode" => mode,
         "execution_mode" => optional_binary(arguments, "execution_mode"),
         "progress" => optional_binary(arguments, "progress"),
         "note" => optional_binary(arguments, "note"),
         "checks" => Map.get(arguments, "checks"),
         "status" => optional_binary(arguments, "status"),
         "output" => Map.get(arguments, "output"),
         "metadata" => Map.get(arguments, "metadata"),
         "project_root" => Arguments.project_root(arguments)
       }}
    end
  end

  defp dispatch(%{"mode" => "status", "task_id" => nil}) do
    {:error, {:invalid_arguments, "`task_id` is required for status mode"}}
  end

  defp dispatch(%{"mode" => "status", "task_id" => task_id, "session_id" => session_id}) do
    case Mission.get_task(task_id) do
      nil ->
        {:error, {:invalid_arguments, "Task not found"}}

      %{session_id: ^session_id} = task ->
        {:ok, task_response(task)}

      _task ->
        {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
  end

  defp dispatch(%{"mode" => "claim", "task_id" => nil}) do
    {:error, {:invalid_arguments, "`task_id` is required for claim mode"}}
  end

  defp dispatch(%{"mode" => "claim", "task_id" => task_id} = normalized) do
    case Platform.claim_task(task_id, nil, %{
           "execution_mode" => normalized["execution_mode"] || "local"
         }) do
      {:ok, task_run} ->
        {:ok,
         %{
           "claimed" => true,
           "task_id" => task_id,
           "run_id" => task_run.id,
           "status" => task_run.status
         }}

      {:error, :not_found} ->
        {:error, {:invalid_arguments, "Task not found"}}

      {:error, :invalid_status} ->
        {:error, {:invalid_arguments, "Task is not in a claimable status"}}

      {:error, reason} ->
        {:error, {:invalid_arguments, "Failed to claim task: #{inspect(reason)}"}}
    end
  end

  defp dispatch(%{"mode" => "complete", "task_id" => nil}) do
    {:error, {:invalid_arguments, "`task_id` is required for complete mode"}}
  end

  defp dispatch(%{"mode" => "complete", "task_id" => task_id, "session_id" => session_id}) do
    case Mission.get_task(task_id) do
      nil ->
        {:error, {:invalid_arguments, "Task not found"}}

      %{session_id: ^session_id} = task ->
        case Mission.complete_task(task) do
          {:ok, updated_task} ->
            {:ok,
             %{
               "completed" => true,
               "task_id" => updated_task.id,
               "title" => updated_task.title,
               "status" => updated_task.status
             }}

          {:error, :unresolved_findings, findings} ->
            {:error,
             {:invalid_arguments,
              "Task has #{length(findings)} unresolved findings; resolve or approve them before completing."}}

          {:error, reason} ->
            {:error, {:invalid_arguments, "Failed to complete task: #{inspect(reason)}"}}
        end

      _task ->
        {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
    end
  end

  defp dispatch(%{"mode" => "heartbeat", "task_id" => nil}) do
    {:error, {:invalid_arguments, "`task_id` is required for heartbeat mode"}}
  end

  defp dispatch(%{"mode" => "heartbeat", "task_id" => task_id} = normalized) do
    case Platform.heartbeat_task(task_id, nil, %{
           "progress" => normalized["progress"],
           "note" => normalized["note"]
         }) do
      {:ok, task_run} ->
        {:ok,
         %{
           "recorded" => true,
           "task_id" => task_id,
           "run_id" => task_run.id
         }}

      {:error, :not_found} ->
        {:error, {:invalid_arguments, "Task run not found; claim the task first"}}

      {:error, reason} ->
        {:error, {:invalid_arguments, "Failed to record heartbeat: #{inspect(reason)}"}}
    end
  end

  defp dispatch(%{"mode" => "checks", "task_id" => nil}) do
    {:error, {:invalid_arguments, "`task_id` is required for checks mode"}}
  end

  defp dispatch(%{"mode" => "checks", "checks" => nil}) do
    {:error, {:invalid_arguments, "`checks` is required for checks mode"}}
  end

  defp dispatch(%{"mode" => "checks", "checks" => checks})
       when not is_list(checks) do
    {:error, {:invalid_arguments, "`checks` must be an array"}}
  end

  defp dispatch(%{"mode" => "checks", "task_id" => task_id, "checks" => checks} = normalized) do
    case Platform.record_task_checks(task_id, nil, checks, normalized["project_root"]) do
      {:ok, results} ->
        {:ok,
         %{
           "recorded" => true,
           "task_id" => task_id,
           "count" => length(results),
           "results" => Enum.map(results, &check_result_response/1)
         }}

      {:error, :not_found} ->
        {:error, {:invalid_arguments, "Task run not found; claim the task first"}}

      {:error, reason} ->
        {:error, {:invalid_arguments, "Failed to record checks: #{inspect(reason)}"}}
    end
  end

  defp dispatch(%{"mode" => "report", "task_id" => nil}) do
    {:error, {:invalid_arguments, "`task_id` is required for report mode"}}
  end

  defp dispatch(%{"mode" => "report", "task_id" => task_id} = normalized) do
    attrs = %{
      "status" => normalized["status"] || "done",
      "output" => normalized["output"] || %{},
      "metadata" => normalized["metadata"] || %{}
    }

    case Platform.report_task(task_id, nil, attrs) do
      {:ok, task_run} ->
        {:ok,
         %{
           "reported" => true,
           "task_id" => task_id,
           "run_id" => task_run.id,
           "status" => task_run.status
         }}

      {:error, :not_found} ->
        {:error, {:invalid_arguments, "Task run not found; claim the task first"}}

      {:error, reason} ->
        {:error, {:invalid_arguments, "Failed to report task: #{inspect(reason)}"}}
    end
  end

  defp task_response(task) do
    %{
      "task_id" => task.id,
      "title" => task.title,
      "status" => task.status,
      "session_id" => task.session_id,
      "position" => task.position,
      "validation_gate" => task.validation_gate
    }
  end

  defp check_result_response(result) do
    metadata = result.metadata || %{}
    payload = result.payload || %{}

    %{
      "id" => result.id,
      "check_type" => result.check_type,
      "status" => result.status,
      "summary" => result.summary,
      "proof_strength" => metadata["proof_strength"],
      "proof" => proof_response(metadata, payload)
    }
  end

  defp proof_response(metadata, payload) do
    %{}
    |> Arguments.maybe_put("proof_strength", metadata["proof_strength"])
    |> Arguments.maybe_put("command", metadata["command"])
    |> Arguments.maybe_put("exit_code", metadata["exit_code"])
    |> Arguments.maybe_put("output_sha256", metadata["output_sha256"] || payload["output_sha256"])
    |> Arguments.maybe_put("output_bytes", metadata["output_bytes"])
    |> Arguments.maybe_put("output_excerpt_bytes", metadata["output_excerpt_bytes"])
    |> Arguments.maybe_put("output_truncated", metadata["output_truncated"])
    |> Arguments.maybe_put("artifact_sha256", metadata["artifact_sha256"])
    |> Arguments.maybe_put("artifact_uri", metadata["artifact_uri"])
    |> Arguments.maybe_put("git_head_sha", metadata["git_head_sha"])
    |> Arguments.maybe_put("working_tree_dirty", metadata["working_tree_dirty"])
  end

  defp mode(arguments) do
    case Map.get(arguments, "mode", "status") do
      value when value in @allowed_modes ->
        {:ok, value}

      _ ->
        {:error,
         {:invalid_arguments, "`mode` must be one of: #{Enum.join(@allowed_modes, ", ")}"}}
    end
  end

  defp optional_binary(arguments, key), do: Arguments.optional_binary_value(arguments, key)
end
