defmodule ControlKeel.MCP.Tools.CkReviewSubmit do
  @moduledoc false

  alias ControlKeel.Mission

  def call(arguments) when is_map(arguments) do
    try do
      do_call(arguments)
    rescue
      e -> {:error, "Review submission failed: #{Exception.message(e)}"}
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp do_call(arguments) do
    attrs =
      Map.take(
        arguments,
        ~w(session_id task_id title review_type submission_body annotations feedback_notes submitted_by metadata previous_review_id plan_phase hypothesis expected_signal research_summary codebase_findings prior_art_summary alignment_context consulted_roles options_considered selected_option rejected_options implementation_steps validation_plan code_snippets agent_spec_id task_spec_id agent_role task_scope out_of_scope business_rules domain_terms persona_or_actor_context allowed_actions prohibited_actions robustness_requirements linked_policy_packs linked_benchmark_suites promotion_gates allowed_semantic_changes forbidden_semantic_changes invariant_boundaries requires_reapproval_if harness_quality_checks scope_estimate)
      )

    case Mission.submit_review(attrs) do
      {:ok, review} ->
        plan_refinement = get_in(review.metadata || %{}, ["plan_refinement"]) || %{}

        browser_url =
          try do
            ControlKeelWeb.Endpoint.url() <> "/reviews/#{review.id}"
          rescue
            _ -> nil
          end

        approval_instructions = approval_instructions(review, browser_url)

        quality = plan_refinement["quality"]

        quality_safe =
          if is_map(quality), do: quality, else: nil

        {:ok,
         %{
           "review_id" => review.id,
           "title" => review.title,
           "review_type" => review.review_type,
           "status" => review.status,
           "session_id" => review.session_id,
           "task_id" => review.task_id,
           "plan_phase" => plan_refinement["phase"],
           "plan_refinement" => plan_refinement,
           "plan_quality" => quality_safe,
           "grill_questions" => get_in(plan_refinement, ["quality", "grill_questions"]) || [],
           "browser_url" => browser_url,
           "review_url" => browser_url,
           "approval_instructions" => approval_instructions,
           "review_roles" => review_roles(review.review_type, plan_refinement)
         }}

      {:error, {:invalid_arguments, reason}} ->
        {:error, {:invalid_arguments, reason}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp approval_instructions(review, nil) do
    %{
      "primary" =>
        "Review #{review.review_type} ##{review.id} in the ControlKeel UI when available.",
      "fallback_status_command" => "controlkeel review status #{review.id}",
      "fallback_approve_command" => "controlkeel review approve #{review.id}",
      "fallback_deny_command" => "controlkeel review deny #{review.id} --feedback '<reason>'"
    }
  end

  defp approval_instructions(review, browser_url) do
    %{
      "primary" => "Open #{browser_url} to approve or deny #{review.review_type} ##{review.id}.",
      "fallback_status_command" => "controlkeel review status #{review.id}",
      "fallback_approve_command" => "controlkeel review approve #{review.id}",
      "fallback_deny_command" => "controlkeel review deny #{review.id} --feedback '<reason>'"
    }
  end

  defp review_roles("completion", _plan_refinement),
    do: ["operator", "security reviewer", "product/human QA"]

  defp review_roles(_review_type, plan_refinement) do
    case Map.get(plan_refinement, "consulted_roles") do
      roles when is_list(roles) and roles != [] -> roles
      _ -> ["operator", "security reviewer", "platform maintainer"]
    end
  end
end
