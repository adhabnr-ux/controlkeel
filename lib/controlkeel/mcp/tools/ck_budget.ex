defmodule ControlKeel.MCP.Tools.CkBudget do
  @moduledoc false

  alias ControlKeel.Budget
  alias ControlKeel.MCP.Arguments

  @allowed_modes ~w(estimate commit status)

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments),
         {:ok, result} <- dispatch(normalized) do
      {:ok, maybe_attach_token_overhead(result, normalized)}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    with {:ok, session_id} <- Arguments.resolve_session_id(arguments),
         {:ok, task_id} <- Arguments.optional_integer(arguments, "task_id"),
         {:ok, mode} <- mode(arguments),
         {:ok, estimated_cost_cents} <-
           optional_non_negative_integer(arguments, "estimated_cost_cents"),
         {:ok, input_tokens} <- optional_non_negative_integer(arguments, "input_tokens"),
         {:ok, cached_input_tokens} <-
           optional_non_negative_integer(arguments, "cached_input_tokens"),
         {:ok, output_tokens} <- optional_non_negative_integer(arguments, "output_tokens"),
         {:ok, include_token_overhead} <-
           Arguments.optional_boolean(arguments, "include_token_overhead") do
      {:ok,
       %{
         "session_id" => session_id,
         "task_id" => task_id,
         "mode" => mode,
         "estimated_cost_cents" => estimated_cost_cents,
         "provider" => optional_binary(arguments, "provider"),
         "model" => optional_binary(arguments, "model"),
         "input_tokens" => input_tokens || 0,
         "cached_input_tokens" => cached_input_tokens || 0,
         "output_tokens" => output_tokens || 0,
         "source" => optional_binary(arguments, "source") || "mcp",
         "tool" => optional_binary(arguments, "tool") || "ck_budget",
         "metadata" => Map.get(arguments, "metadata", %{}),
         "project_root" => optional_binary(arguments, "project_root"),
         "include_token_overhead" => include_token_overhead || false
       }}
    end
  end

  defp dispatch(%{"mode" => "estimate"} = normalized), do: Budget.estimate(normalized)
  defp dispatch(%{"mode" => "commit"} = normalized), do: Budget.commit(normalized)
  defp dispatch(%{"mode" => "status"} = normalized), do: Budget.status(normalized)

  defp maybe_attach_token_overhead(result, %{
         "include_token_overhead" => true,
         "project_root" => project_root
       })
       when is_binary(project_root) do
    token_overhead = token_overhead_summary(project_root)

    result
    |> Map.put("token_overhead", token_overhead)
    |> Map.put("token_overhead_deprecated", true)
    |> Map.put(
      "token_overhead_hint",
      "Prefer `ck_observability` (report=costs) for token/cost overhead — `include_token_overhead` runs 3 synchronous audits and is deprecated."
    )
  end

  defp maybe_attach_token_overhead(result, _normalized), do: result

  defp token_overhead_summary(project_root) do
    audit_rules =
      ControlKeel.MCP.Tools.CkTokenAudit.call(%{
        "project_root" => project_root,
        "mode" => "rules"
      })

    audit_skills =
      ControlKeel.MCP.Tools.CkTokenAudit.call(%{
        "project_root" => project_root,
        "mode" => "skills"
      })

    audit_tools =
      ControlKeel.MCP.Tools.CkTokenAudit.call(%{
        "project_root" => project_root,
        "mode" => "tools"
      })

    %{
      "rules" => audit_payload(audit_rules),
      "skills" => audit_payload(audit_skills),
      "tools" => audit_payload(audit_tools)
    }
  end

  defp audit_payload({:ok, payload}) when is_map(payload) do
    estimated_tokens =
      Map.get(payload, "estimated_tokens") ||
        Map.get(payload, "total_tokens") ||
        Map.get(payload, "total_skill_tokens")

    %{
      "estimated_tokens" => estimated_tokens,
      "recommendations" => Map.get(payload, "recommendations")
    }
  end

  defp audit_payload(_), do: %{"estimated_tokens" => nil, "recommendations" => []}

  defp mode(arguments) do
    case Map.get(arguments, "mode", "estimate") do
      value when value in @allowed_modes -> {:ok, value}
      _ -> {:error, {:invalid_arguments, "`mode` must be `estimate`, `commit`, or `status`"}}
    end
  end

  defp optional_non_negative_integer(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value -> normalize_integer(value, key)
    end
  end

  defp normalize_integer(value, key) do
    case Arguments.normalize_integer(value, key) do
      {:ok, parsed} when parsed >= 0 -> {:ok, parsed}
      _ -> {:error, {:invalid_arguments, "`#{key}` must be a non-negative integer if provided"}}
    end
  end

  defp optional_binary(arguments, key), do: Arguments.optional_binary_value(arguments, key)
end
