defmodule ControlKeel.Benchmark.Metadata do
  @moduledoc false

  alias ControlKeel.Intent.Domains
  alias ControlKeel.Utils

  # Documented eval_source values for scenario metadata
  @valid_eval_sources ~w(production_trace synthetic review_feedback operator_debrief red_team)

  # Documented eval_mode values
  @valid_eval_modes ~w(deterministic llm_judge human_golden)

  # Documented failure_dimension values
  @valid_failure_dimensions ~w(correctness faithfulness safety schema groundedness task_completion)

  # Documented signal_source values (production signal eval seeds)
  @valid_signal_sources ~w(explicit implicit trajectory self_diagnostic)

  @agent_spec_string_fields ~w(
    agent_spec_id agent_spec_version task_spec_id agent_role task_scope persona_or_actor_context
  )

  @skill_eval_string_fields ~w(
    skill_name skill_variant baseline_variant skill_delta_score
  )

  @agent_spec_list_fields ~w(
    out_of_scope business_rules domain_terms allowed_actions prohibited_actions
    robustness_requirements linked_policy_packs linked_benchmark_suites promotion_gates
  )

  @skill_eval_boolean_fields ~w(skill_loaded baseline_without_skill skill_harmed_performance)

  def normalize_scenario_metadata(payload) when is_map(payload) do
    metadata =
      payload
      |> Map.get("metadata", %{})
      |> Utils.stringify_keys_deep()

    base = %{
      "task_type" => infer_task_type(payload, metadata),
      "risk_tier" => infer_risk_tier(payload, metadata),
      "domain_pack" => infer_domain_pack(payload, metadata),
      "budget_tier" => infer_budget_tier(payload, metadata),
      "eval_source" => infer_eval_source(payload, metadata),
      "eval_mode" => infer_eval_mode(payload, metadata),
      "failure_dimension" => infer_failure_dimension(payload, metadata)
    }

    base
    |> Map.merge(metadata)
    |> normalize_eval_fields()
  end

  def normalize_scenario_metadata(_payload), do: default_metadata()

  def suite_internal?(%{metadata: metadata}) when is_map(metadata) do
    internal_metadata?(metadata)
  end

  def suite_internal?(payload) when is_map(payload) do
    internal_metadata?(Map.get(payload, "metadata", %{}))
  end

  def suite_internal?(_payload), do: false

  @doc """
  Normalizes run-level metadata vocabulary for regression comparisons,
  red-team evidence, and experiment tracking.

  This helper only coerces documented metadata fields; callers must explicitly
  use it in import or run-creation paths when they want normalization.
  """
  def normalize_run_metadata(metadata) when is_map(metadata) do
    metadata
    |> Utils.stringify_keys_deep()
    |> normalize_eval_fields()
  end

  def normalize_run_metadata(_), do: %{}

  @doc """
  Returns the set of valid eval_source values for scenario metadata.
  Used by importers and validators to check provenance labels.
  """
  def valid_eval_sources, do: @valid_eval_sources

  @doc """
  Returns the set of valid eval_mode values.
  """
  def valid_eval_modes, do: @valid_eval_modes

  @doc """
  Returns the set of valid failure_dimension values.
  """
  def valid_failure_dimensions, do: @valid_failure_dimensions

  @doc """
  Returns the set of valid signal_source values for production-signal-derived evals.
  """
  def valid_signal_sources, do: @valid_signal_sources

  @doc """
  Returns the scenario metadata fields required for benchmark provenance.
  """
  def required_eval_fields, do: ~w(eval_source eval_mode failure_dimension)

  @doc """
  Checks whether normalized metadata has the required benchmark provenance fields.
  """
  def metadata_complete?(metadata) when is_map(metadata) do
    Enum.all?(required_eval_fields(), fn field ->
      case Map.get(metadata, field) do
        value when is_binary(value) -> String.trim(value) != ""
        _ -> false
      end
    end)
  end

  def metadata_complete?(_metadata), do: false

  @doc """
  Returns documented Agent/Task Spec metadata fields grouped by expected shape.
  """
  def agent_spec_fields do
    %{
      "string" => @agent_spec_string_fields,
      "string_list" => @agent_spec_list_fields,
      "skill_eval_string" => @skill_eval_string_fields,
      "skill_eval_boolean" => @skill_eval_boolean_fields
    }
  end

  def default_metadata do
    %{
      "task_type" => "backend",
      "risk_tier" => "medium",
      "domain_pack" => "software",
      "budget_tier" => "medium"
    }
  end

  # Validates and coerces the documented eval/signal metadata fields.
  # Unknown values are kept as-is (open map); known fields are validated.
  defp normalize_eval_fields(metadata) do
    metadata
    |> coerce_enum("eval_source", @valid_eval_sources)
    |> coerce_enum("eval_mode", @valid_eval_modes)
    |> coerce_enum("failure_dimension", @valid_failure_dimensions)
    |> coerce_enum("signal_source", @valid_signal_sources)
    |> normalize_agent_spec_fields()
    |> normalize_skill_eval_fields()
  end

  defp normalize_agent_spec_fields(metadata) do
    metadata
    |> normalize_string_fields(@agent_spec_string_fields)
    |> normalize_string_list_fields(@agent_spec_list_fields)
  end

  defp normalize_skill_eval_fields(metadata) do
    metadata
    |> normalize_string_fields(@skill_eval_string_fields)
    |> normalize_boolean_fields(@skill_eval_boolean_fields)
  end

  defp normalize_string_fields(metadata, fields) do
    Enum.reduce(fields, metadata, fn key, acc ->
      case Map.get(acc, key) do
        nil ->
          acc

        value when is_binary(value) ->
          case String.trim(value) do
            "" -> Map.delete(acc, key)
            trimmed -> Map.put(acc, key, trimmed)
          end

        _ ->
          Map.delete(acc, key)
      end
    end)
  end

  defp normalize_string_list_fields(metadata, fields) do
    Enum.reduce(fields, metadata, fn key, acc ->
      case Map.get(acc, key) do
        nil ->
          acc

        values when is_list(values) ->
          normalized =
            values
            |> Enum.filter(&is_binary/1)
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          if normalized == [], do: Map.delete(acc, key), else: Map.put(acc, key, normalized)

        _ ->
          Map.delete(acc, key)
      end
    end)
  end

  defp normalize_boolean_fields(metadata, fields) do
    Enum.reduce(fields, metadata, fn key, acc ->
      case Map.get(acc, key) do
        nil -> acc
        value when is_boolean(value) -> Map.put(acc, key, value)
        "true" -> Map.put(acc, key, true)
        "false" -> Map.put(acc, key, false)
        _ -> Map.delete(acc, key)
      end
    end)
  end

  defp coerce_enum(metadata, key, valid_values) do
    case Map.get(metadata, key) do
      nil ->
        metadata

      value when is_binary(value) ->
        if value in valid_values, do: metadata, else: Map.delete(metadata, key)

      _ ->
        Map.delete(metadata, key)
    end
  end

  defp infer_task_type(payload, metadata) do
    metadata["task_type"] ||
      cond do
        category(payload) in ["privacy", "compliance"] -> "review"
        path(payload) =~ ~r/\.(css|tsx|jsx|html)$/ -> "ui"
        path(payload) =~ ~r/(docker|compose|config|production|infra|deploy)/ -> "deploy"
        true -> "backend"
      end
  end

  defp infer_risk_tier(payload, metadata) do
    metadata["risk_tier"] ||
      cond do
        category(payload) == "privacy" -> "high"
        Map.get(payload, "expected_decision") == "block" -> "high"
        true -> "moderate"
      end
  end

  defp infer_domain_pack(payload, metadata) do
    case normalize_domain_pack(metadata["domain_pack"]) do
      nil ->
        payload
        |> domain_hint_blob(metadata)
        |> infer_domain_pack_from_text()

      pack ->
        pack
    end
  end

  defp infer_budget_tier(payload, metadata) do
    metadata["budget_tier"] ||
      cond do
        path(payload) =~ ~r/(docker|deploy|infra|production)/ -> "high"
        category(payload) == "security" -> "medium"
        true -> "low"
      end
  end

  defp infer_eval_source(payload, metadata) do
    metadata["eval_source"] ||
      cond do
        metadata["source"] == "controlkeel_internal" -> "red_team"
        metadata["host_pattern"] in ["copilot", "opencode", "both"] -> "red_team"
        category(payload) == "security" -> "red_team"
        true -> "synthetic"
      end
  end

  defp infer_eval_mode(_payload, metadata), do: metadata["eval_mode"] || "deterministic"

  defp infer_failure_dimension(payload, metadata) do
    metadata["failure_dimension"] ||
      cond do
        category(payload) in ["security", "privacy", "compliance"] -> "safety"
        Map.get(payload, "expected_rules", []) != [] -> "schema"
        true -> "correctness"
      end
  end

  defp internal_metadata?(metadata) when is_map(metadata) do
    case Map.get(metadata, "internal") do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp category(payload), do: String.downcase(Map.get(payload, "category", ""))
  defp path(payload), do: String.downcase(Map.get(payload, "path", ""))

  defp domain_hint_blob(payload, metadata) do
    [
      Map.get(payload, "incident_label", ""),
      Map.get(payload, "name", ""),
      Map.get(payload, "path", ""),
      Map.get(metadata, "prompt", "")
    ]
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp infer_domain_pack_from_text(text) do
    cond do
      String.contains?(text, ["claim", "policyholder", "adjuster", "underwriting", "premium"]) ->
        "insurance"

      String.contains?(text, ["patient", "medical", "phi", "clinic", "diagnosis"]) ->
        "healthcare"

      String.contains?(text, ["student", "school", "classroom", "minor"]) ->
        "education"

      String.contains?(text, ["payment", "invoice", "bank", "ledger", "transaction"]) ->
        "finance"

      String.contains?(text, ["candidate", "resume", "employee", "salary", "hiring"]) ->
        "hr"

      String.contains?(text, ["privileged", "matter", "litigation", "contract", "ediscovery"]) ->
        "legal"

      String.contains?(text, ["consent", "subscriber", "campaign", "analytics", "tracking"]) ->
        "marketing"

      String.contains?(text, ["crm", "lead", "prospect", "pipeline", "quota", "deal"]) ->
        "sales"

      String.contains?(text, ["listing", "tenant", "mortgage", "property", "rental"]) ->
        "realestate"

      String.contains?(text, ["constituent", "permit", "benefits", "public record", "caseworker"]) ->
        "government"

      String.contains?(text, ["cart", "checkout", "refund", "chargeback", "order"]) ->
        "ecommerce"

      String.contains?(text, ["shipment", "dispatch", "warehouse", "carrier", "manifest"]) ->
        "logistics"

      String.contains?(text, ["qa", "quality hold", "work order", "supplier", "production"]) ->
        "manufacturing"

      String.contains?(text, ["donor", "grant", "volunteer", "beneficiary", "fundraising"]) ->
        "nonprofit"

      true ->
        "software"
    end
  end

  defp normalize_domain_pack(nil), do: nil

  defp normalize_domain_pack(value) do
    pack = Domains.normalize_pack(value, "__unsupported__")
    if Domains.supported_pack?(pack), do: pack, else: nil
  end
end
