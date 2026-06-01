defmodule ControlKeel.MCP.Tools.CkContextPack do
  @moduledoc false

  alias ControlKeel.Memory
  alias ControlKeel.MCP.Arguments
  alias ControlKeel.Mission

  @default_top_k 5
  @max_top_k 10

  def call(arguments) when is_map(arguments) do
    with {:ok, task_id} <- Arguments.optional_integer(arguments, "task_id"),
         {:ok, top_k} <-
           Arguments.optional_top_k(arguments, default: @default_top_k, max: @max_top_k),
         {:ok, session} <- Arguments.fetch_session(arguments, preload_context: true),
         {:ok, task} <- resolve_task(session, task_id),
         {:ok, exclude_ids} <- normalize_exclude_ids(Map.get(arguments, "exclude_ids")),
         count_only = Map.get(arguments, "count_only") == true,
         {:ok, pack} <- build_pack(arguments, session, task, top_k, exclude_ids, count_only) do
      {:ok, pack}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp build_pack(arguments, session, task, top_k, exclude_ids, count_only) do
    query = normalize_query(arguments, session, task)
    detail_level = normalize_detail_level(Map.get(arguments, "detail_level"))
    excerpt_limit = excerpt_limit(detail_level)
    domain_pack = get_in(session.execution_brief || %{}, ["domain_pack"])

    search_result =
      Memory.search(query,
        workspace_id: session.workspace_id,
        session_id: session.id,
        task_id: task && task.id,
        domain_pack: domain_pack,
        top_k: top_k,
        include_body: true
      )

    entries =
      search_result.entries
      |> Enum.reject(&(&1.id in exclude_ids))

    if count_only do
      tag_dist = Enum.frequencies_by(entries, fn e -> List.first(e.tags || []) end)

      {:ok,
       %{
         "session_id" => session.id,
         "task_id" => task && task.id,
         "query" => query,
         "count_only" => true,
         "hit_count" => length(entries),
         "tag_distribution" => tag_dist,
         "semantic_available" => search_result.semantic_available
       }}
    else
      proof_summary = Mission.proof_summary_for_task(task)
      resume_packet = build_resume_packet(task)

      {:ok,
       %{
         "session_id" => session.id,
         "task_id" => task && task.id,
         "query" => query,
         "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
         "factual_only" => true,
         "detail_level" => detail_level,
         "semantic_available" => search_result.semantic_available,
         "retrieval_strategy" => search_result[:retrieval_strategy],
         "excluded_ids_count" => length(exclude_ids),
         "context_pack" => %{
           "task" => task_facts(session, task),
           "proof" => proof_facts(proof_summary),
           "resume" => resume_facts(resume_packet),
           "memory" => Enum.map(entries, &memory_entry(&1, excerpt_limit)),
           "citations" => citations(task, proof_summary, resume_packet, entries)
         }
       }}
    end
  end

  defp normalize_exclude_ids(nil), do: {:ok, []}

  defp normalize_exclude_ids(ids) when is_list(ids) do
    parsed =
      Enum.reduce_while(ids, [], fn id, acc ->
        cond do
          is_integer(id) ->
            {:cont, [id | acc]}

          is_binary(id) ->
            case Integer.parse(id) do
              {n, ""} -> {:cont, [n | acc]}
              _ -> {:halt, :error}
            end

          true ->
            {:halt, :error}
        end
      end)

    case parsed do
      :error -> {:error, {:invalid_arguments, "`exclude_ids` must be a list of integers"}}
      ids -> {:ok, ids}
    end
  end

  defp normalize_exclude_ids(_),
    do: {:error, {:invalid_arguments, "`exclude_ids` must be a list"}}

  defp resolve_task(session, nil) do
    task =
      Enum.find(session.tasks, &(&1.status == "in_progress")) ||
        Enum.find(session.tasks, &(&1.status == "queued")) ||
        List.first(session.tasks)

    {:ok, task}
  end

  defp resolve_task(session, task_id) do
    case Enum.find(session.tasks, &(&1.id == task_id)) do
      nil -> {:error, {:invalid_arguments, "`task_id` must belong to the current session"}}
      task -> {:ok, task}
    end
  end

  defp build_resume_packet(nil), do: nil

  defp build_resume_packet(task) do
    case Mission.resume_packet(task.id) do
      {:ok, packet} -> packet
      _ -> nil
    end
  end

  defp task_facts(session, nil) do
    %{
      "session_title" => session.title,
      "objective" => session.objective,
      "risk_tier" => session.risk_tier,
      "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"])
    }
  end

  defp task_facts(session, task) do
    %{
      "id" => task.id,
      "title" => task.title,
      "status" => task.status,
      "validation_gate" => task.validation_gate,
      "session_title" => session.title,
      "objective" => session.objective,
      "risk_tier" => session.risk_tier,
      "domain_pack" => get_in(session.execution_brief || %{}, ["domain_pack"])
    }
  end

  defp proof_facts(nil), do: nil

  defp proof_facts(proof_summary) do
    %{
      "proof_id" => proof_summary["id"],
      "version" => proof_summary["version"],
      "status" => proof_summary["status"],
      "deploy_ready" => proof_summary["deploy_ready"],
      "risk_score" => proof_summary["risk_score"],
      "verification_status" => proof_summary["verification_status"],
      "verification_score" => proof_summary["verification_score"],
      "blocked_findings_count" => proof_summary["blocked_findings_count"],
      "open_findings_count" => proof_summary["open_findings_count"]
    }
  end

  defp resume_facts(nil), do: nil

  defp resume_facts(packet) do
    unresolved = packet["unresolved_findings"] || []
    latest_invocations = packet["latest_invocations"] || []

    %{
      "task_status" => packet["task_status"],
      "review_gate" => packet["review_gate"],
      "unresolved_findings_count" => length(unresolved),
      "latest_invocations_count" => length(latest_invocations),
      "memory_hits_count" => length(packet["memory_hits"] || []),
      "workspace_cache_key" => packet["workspace_cache_key"]
    }
  end

  defp memory_entry(entry, excerpt_limit) do
    %{
      "id" => entry.id,
      "record_type" => entry.record_type,
      "title" => entry.title,
      "summary" => entry.summary,
      "excerpt" => clip_text(entry.body, excerpt_limit),
      "tags" => entry.tags,
      "source_type" => entry.source_type,
      "source_id" => entry.source_id,
      "session_id" => entry.session_id,
      "task_id" => entry.task_id,
      "inserted_at" => entry.inserted_at,
      "score" => entry.score
    }
  end

  defp citations(task, proof_summary, resume_packet, memory_entries) do
    memory_citations =
      Enum.map(memory_entries, fn entry ->
        %{
          "kind" => "memory",
          "memory_id" => entry.id,
          "record_type" => entry.record_type,
          "title" => entry.title,
          "source_type" => entry.source_type,
          "task_id" => entry.task_id,
          "inserted_at" => entry.inserted_at
        }
      end)

    proof_citation =
      if proof_summary do
        [
          %{
            "kind" => "proof",
            "proof_id" => proof_summary["id"],
            "task_id" => proof_summary["task_id"],
            "version" => proof_summary["version"],
            "generated_at" => proof_summary["generated_at"]
          }
        ]
      else
        []
      end

    resume_citation =
      if task && resume_packet do
        [
          %{
            "kind" => "resume_packet",
            "task_id" => task.id,
            "task_status" => resume_packet["task_status"],
            "workspace_cache_key" => resume_packet["workspace_cache_key"]
          }
        ]
      else
        []
      end

    proof_citation ++ resume_citation ++ memory_citations
  end

  defp normalize_query(arguments, session, task) do
    case Map.get(arguments, "query") do
      value when is_binary(value) and value != "" ->
        String.trim(value)

      _ ->
        [
          session.objective,
          task && task.title,
          task && task.validation_gate,
          get_in(session.execution_brief || %{}, ["domain_pack"])
        ]
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.join(" ")
    end
  end

  defp normalize_detail_level(value) when value in ["full", :full], do: "full"
  defp normalize_detail_level(_value), do: "compact"

  defp excerpt_limit("full"), do: 1_200
  defp excerpt_limit(_detail_level), do: 360

  defp clip_text(nil, _limit), do: ""
  defp clip_text(text, limit) when byte_size(text) <= limit, do: text
  defp clip_text(text, limit), do: binary_part(text, 0, limit) <> "…"
end
