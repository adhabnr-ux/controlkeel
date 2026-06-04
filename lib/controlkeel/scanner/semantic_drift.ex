defmodule ControlKeel.Scanner.SemanticDrift do
  @moduledoc false

  alias ControlKeel.Mission
  alias ControlKeel.Scanner.Finding

  @fields [
    {"forbidden_semantic_changes", "semantic_drift.forbidden_change",
     "Change appears to match a semantic behavior change forbidden by the approved plan."},
    {"requires_reapproval_if", "semantic_drift.reapproval_required",
     "Change appears to match a condition that requires human re-approval before continuing."}
  ]

  def detect(%{"content" => content, "task_id" => task_id} = input)
      when is_binary(content) and is_integer(task_id) do
    with %{} = review <- Mission.latest_review_for_task(task_id, "plan"),
         true <- review.status == "approved",
         %{} = refinement <- get_in(review.metadata || %{}, ["plan_refinement"]) do
      normalized_content = normalize_text(content)

      @fields
      |> Enum.flat_map(fn {field, rule_id, message} ->
        refinement
        |> Map.get(field, [])
        |> List.wrap()
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.filter(&matches_boundary?(normalized_content, &1))
        |> Enum.map(&finding(input, rule_id, message, field, &1, review.id))
      end)
      |> uniq_findings()
    else
      _ -> []
    end
  end

  def detect(_input), do: []

  defp matches_boundary?(normalized_content, boundary) do
    normalized_boundary = normalize_text(boundary)

    byte_size(normalized_boundary) >= 6 and
      (String.contains?(normalized_content, normalized_boundary) or
         token_overlap_match?(normalized_content, normalized_boundary))
  end

  defp token_overlap_match?(normalized_content, normalized_boundary) do
    boundary_tokens = significant_tokens(normalized_boundary)
    content_tokens = normalized_content |> significant_tokens() |> MapSet.new()
    overlap_count = Enum.count(boundary_tokens, &MapSet.member?(content_tokens, &1))

    length(boundary_tokens) >= 3 and overlap_count >= required_overlap(length(boundary_tokens))
  end

  defp significant_tokens(value) do
    value
    |> String.split(" ", trim: true)
    |> Enum.map(&normalize_token/1)
    |> Enum.reject(
      &(&1 in ["", "a", "an", "and", "by", "for", "if", "in", "of", "or", "the", "to"])
    )
    |> Enum.uniq()
  end

  defp normalize_token("alter"), do: "change"
  defp normalize_token("altered"), do: "change"
  defp normalize_token("changes"), do: "change"
  defp normalize_token("changed"), do: "change"
  defp normalize_token("changing"), do: "change"
  defp normalize_token("gating"), do: "gate"
  defp normalize_token("gated"), do: "gate"
  defp normalize_token("semantics"), do: "semantic"
  defp normalize_token("behaviour"), do: "behavior"

  defp normalize_token(token) do
    cond do
      String.ends_with?(token, "ies") and byte_size(token) > 4 ->
        String.replace_suffix(token, "ies", "y")

      String.ends_with?(token, "s") and byte_size(token) > 4 ->
        String.trim_trailing(token, "s")

      true ->
        token
    end
  end

  defp required_overlap(boundary_count) do
    max(3, ceil(boundary_count * 0.75))
  end

  defp finding(input, rule_id, message, field, boundary, review_id) do
    %Finding{
      id: fingerprint(rule_id, input, field, boundary, review_id),
      severity: "medium",
      category: "governance",
      rule_id: rule_id,
      decision: "warn",
      plain_message: message,
      location: %{
        "path" => Map.get(input, "path"),
        "kind" => Map.get(input, "kind", "text")
      },
      metadata: %{
        "scanner" => "semantic_drift",
        "plan_review_id" => review_id,
        "plan_field" => field,
        "matched_boundary" => boundary
      }
    }
  end

  defp normalize_text(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, " ")
    |> String.trim()
  end

  defp uniq_findings(findings) do
    Enum.uniq_by(findings, & &1.id)
  end

  defp fingerprint(rule_id, input, field, boundary, review_id) do
    seed =
      [
        rule_id,
        Map.get(input, "path"),
        Map.get(input, "task_id"),
        field,
        boundary,
        review_id
      ]
      |> Enum.map(&to_string/1)
      |> Enum.join(":")

    "fp_" <> (:crypto.hash(:sha256, seed) |> Base.encode16(case: :lower) |> binary_part(0, 12))
  end
end
