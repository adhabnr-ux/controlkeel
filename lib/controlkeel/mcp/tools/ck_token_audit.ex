defmodule ControlKeel.MCP.Tools.CkTokenAudit do
  @moduledoc false

  @target_word_count 1200
  @words_per_token 0.75
  @chars_per_token 4

  def call(arguments) when is_map(arguments) do
    with {:ok, normalized} <- normalize(arguments) do
      project_root = normalized["project_root"] || File.cwd!()
      mode = normalized["mode"] || "full"

      case mode do
        "full" ->
          audit_full(project_root)

        "skills" ->
          audit_skills(project_root)

        "rules" ->
          audit_rules_only(project_root)

        "tools" ->
          audit_tools()

        "amplification" ->
          audit_amplification(normalized)

        _ ->
          {:error,
           {:invalid_arguments,
            "mode must be 'full', 'skills', 'rules', 'tools', or 'amplification'"}}
      end
    end
  end

  def call(_arguments), do: {:error, {:invalid_arguments, "Tool arguments must be an object"}}

  defp normalize(arguments) do
    {:ok,
     %{
       "project_root" => Map.get(arguments, "project_root"),
       "mode" => Map.get(arguments, "mode", "full"),
       "session_id" => Map.get(arguments, "session_id"),
       "limit" => Map.get(arguments, "limit", 20)
     }}
  end

  defp audit_amplification(%{"session_id" => session_id, "limit" => limit}) do
    alias ControlKeel.Budget

    opts =
      [limit: limit]
      |> then(fn o -> if session_id, do: [{:session_id, session_id} | o], else: o end)

    ratios = Budget.amplification_ratios(opts)

    flagged = Enum.filter(ratios, &(&1.ratio >= 5.0))

    {:ok,
     %{
       "mode" => "amplification",
       "session_id" => session_id,
       "total_sessions" => length(ratios),
       "flagged_count" => length(flagged),
       "ratios" =>
         Enum.map(ratios, fn r ->
           %{
             "session_id" => r.session_id,
             "workspace_id" => r.workspace_id,
             "ratio" => Float.round(r.ratio, 3),
             "input_tokens" => r.input_tokens,
             "output_tokens" => r.output_tokens,
             "flag" => if(r.ratio >= 20.0, do: "danger", else: if(r.ratio >= 5.0, do: "warn", else: "ok"))
           }
         end),
       "recommendations" => build_amplification_recommendations(flagged)
     }}
  end

  defp build_amplification_recommendations([]), do: ["No sessions exceed the 5× amplification threshold."]

  defp build_amplification_recommendations(flagged) do
    danger = Enum.count(flagged, &(&1.ratio >= 20.0))
    warn = length(flagged) - danger

    recs = []

    recs =
      if danger > 0 do
        ["#{danger} session(s) exceed 20× output amplification — investigate for runaway generation" | recs]
      else
        recs
      end

    recs =
      if warn > 0 do
        ["#{warn} session(s) exceed 5× output amplification — review for verbosity or prompt injection" | recs]
      else
        recs
      end

    Enum.reverse(recs)
  end

  defp audit_full(project_root) do
    with {:ok, rules_data} <- audit_rules_only(project_root),
         {:ok, skills_data} <- audit_skills(project_root) do
      {:ok,
       Map.merge(rules_data, %{
         "skills" => skills_data["skills"],
         "skill_duplicates" => skills_data["duplicates"],
         "duplicate_token_count" => skills_data["duplicate_token_count"],
         "duplicate_word_count" => skills_data["duplicate_word_count"],
         "total_skill_tokens" => skills_data["total_skill_tokens"],
         "total_skill_words" => skills_data["total_skill_words"],
         "skill_recommendations" => skills_data["recommendations"]
       })}
    end
  end

  @project_skill_subdirs [
    ".agents/skills",
    ".codex/skills",
    ".claude/skills",
    ".copilot/skills",
    ".github/skills",
    ".cline/skills",
    ".roo/skills",
    ".cursor/skills",
    ".opencode/skills",
    ".augment/skills",
    ".continue/skills",
    ".hermes/skills",
    ".factory/skills",
    "skills"
  ]

  @user_skill_subdirs [
    ".agents/skills",
    ".codex/skills",
    ".claude/skills",
    ".copilot/skills",
    ".cline/skills",
    ".roo/skills",
    ".hermes/skills",
    ".factory/skills",
    ".openclaw/skills"
  ]

  defp audit_skills(project_root) do
    user_home =
      System.get_env("CONTROLKEEL_HOME") || System.get_env("HOME") || System.user_home!()

    user_skills =
      Enum.flat_map(@user_skill_subdirs, fn subdir ->
        dir = Path.join(user_home, subdir)
        list_skills(dir, "user:#{Path.dirname(subdir)}")
      end)

    project_skills =
      Enum.flat_map(@project_skill_subdirs, fn subdir ->
        dir = Path.join(project_root, subdir)
        list_skills(dir, "project:#{subdir}")
      end)

    all_skills = user_skills ++ project_skills

    # Find duplicates by skill name
    duplicates = find_duplicate_skills(all_skills)

    # Calculate token cost
    total_skill_words = Enum.sum(Enum.map(all_skills, & &1["word_count"]))
    total_skill_tokens = estimate_tokens_from_words(total_skill_words)
    duplicate_words = Enum.sum(Enum.map(duplicates, & &1["total_word_count"]))
    duplicate_tokens = estimate_tokens_from_words(duplicate_words)

    recommendations = build_skill_recommendations(all_skills, duplicates)

    {:ok,
     %{
       "skills" => all_skills,
       "duplicates" => duplicates,
       "total_skill_words" => total_skill_words,
       "total_skill_tokens" => total_skill_tokens,
       "duplicate_word_count" => duplicate_words,
       "duplicate_token_count" => duplicate_tokens,
       "recommendations" => recommendations
     }}
  end

  defp audit_tools do
    alias ControlKeel.MCP.Protocol

    # Always measure the full schema set so savings calculations are accurate regardless
    # of which groups the user has currently active via CK_TOOL_GROUPS.
    tool_schemas = Protocol.tool_schemas(tool_groups: :all)
    available_groups = Protocol.tool_groups()

    # Calculate size for each tool schema
    tool_measurements =
      Enum.map(tool_schemas, fn tool_schema ->
        schema_json = Jason.encode!(tool_schema)
        char_count = String.length(schema_json)
        estimated_tokens = estimate_tokens_from_chars(char_count)

        %{
          "name" => tool_schema["name"],
          "description" => tool_schema["description"],
          "char_count" => char_count,
          "estimated_tokens" => estimated_tokens
        }
      end)

    total_chars = Enum.sum(Enum.map(tool_measurements, & &1["char_count"]))
    total_tokens = Enum.sum(Enum.map(tool_measurements, & &1["estimated_tokens"]))
    tool_count = length(tool_measurements)

    # Sort by token cost (descending)
    sorted_tools = Enum.sort_by(tool_measurements, & &1["estimated_tokens"], :desc)

    # Identify largest tools (top 20% or at least top 5)
    large_tool_count = max(5, div(tool_count, 5))
    largest_tools = Enum.take(sorted_tools, large_tool_count)

    # Calculate token savings for different group combinations
    group_savings = calculate_group_savings(tool_measurements, available_groups)

    recommendations =
      build_tool_recommendations(tool_measurements, total_tokens, tool_count, group_savings)

    {:ok,
     %{
       "tools" => sorted_tools,
       "largest_tools" => largest_tools,
       "tool_count" => tool_count,
       "total_chars" => total_chars,
       "total_tokens" => total_tokens,
       "avg_tokens_per_tool" => if(tool_count > 0, do: div(total_tokens, tool_count), else: 0),
       "available_groups" => available_groups,
       "group_savings" => group_savings,
       "recommendations" => recommendations
     }}
  end

  defp audit_rules_only(project_root) do
    # Check for rule files
    rule_files = find_rule_files(project_root)

    if Enum.empty?(rule_files) do
      {:ok,
       %{
         "project_root" => project_root,
         "rule_files" => [],
         "total_words" => 0,
         "estimated_tokens" => 0,
         "status" => "no_rules",
         "recommendations" => ["No rule files found (AGENTS.md, CLAUDE.md)"]
       }}
    else
      audit_results = Enum.map(rule_files, &audit_rule_file/1)

      total_words = Enum.sum(Enum.map(audit_results, & &1["word_count"]))
      total_tokens = estimate_tokens_from_words(total_words)

      status = if total_words > @target_word_count, do: "oversized", else: "optimal"

      recommendations = build_recommendations(audit_results, total_words)

      {:ok,
       %{
         "project_root" => project_root,
         "rule_files" => audit_results,
         "total_words" => total_words,
         "estimated_tokens" => total_tokens,
         "target_word_count" => @target_word_count,
         "status" => status,
         "recommendations" => recommendations
       }}
    end
  end

  defp find_rule_files(project_root) do
    # Covers all major host-specific instruction/rule file locations.
    # Glob patterns (containing "*") are expanded; plain paths are checked directly.
    candidates = [
      # Standard multi-agent convention files
      Path.join([project_root, "AGENTS.md"]),
      Path.join([project_root, "CLAUDE.md"]),
      Path.join([project_root, "GEMINI.md"]),
      Path.join([project_root, "AIDER.md"]),
      # Claude
      Path.join([project_root, ".claude", "CLAUDE.md"]),
      # Cursor
      Path.join([project_root, ".cursor", "rules", "*.mdc"]),
      # Windsurf
      Path.join([project_root, ".windsurf", "rules", "*.md"]),
      # Augment
      Path.join([project_root, ".augment", "rules", "*.md"]),
      # Cline
      Path.join([project_root, ".clinerules"]),
      Path.join([project_root, ".clinerules", "*.md"]),
      # Roo
      Path.join([project_root, ".roo", "rules", "*.md"]),
      # GitHub Copilot
      Path.join([project_root, ".github", "copilot-instructions.md"])
    ]

    candidates
    |> Enum.flat_map(fn path ->
      if String.contains?(path, "*") do
        Path.wildcard(path)
      else
        if File.exists?(path) and not File.dir?(path), do: [path], else: []
      end
    end)
    |> Enum.uniq()
  end

  defp audit_rule_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        word_count = count_words(content)
        char_count = String.length(content)
        tokens_from_words = estimate_tokens_from_words(word_count)
        tokens_from_chars = estimate_tokens_from_chars(char_count)
        # Use the more conservative (larger) estimate
        estimated_tokens = max(tokens_from_words, tokens_from_chars)

        %{
          "path" => file_path,
          "word_count" => word_count,
          "char_count" => char_count,
          "estimated_tokens" => estimated_tokens,
          "oversized" => word_count > @target_word_count
        }

      {:error, _reason} ->
        %{
          "path" => file_path,
          "error" => "unreadable",
          "word_count" => 0,
          "char_count" => 0,
          "estimated_tokens" => 0,
          "oversized" => false
        }
    end
  end

  defp count_words(content) do
    content
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp estimate_tokens_from_words(word_count) do
    round(word_count / @words_per_token)
  end

  defp estimate_tokens_from_chars(char_count) do
    round(char_count / @chars_per_token)
  end

  defp build_recommendations(audit_results, total_words) do
    recommendations = []

    # Check overall size
    recommendations =
      if total_words > @target_word_count do
        ratio = Float.round(total_words / @target_word_count, 1)

        [
          "Total rule file size is #{ratio}x the target of #{@target_word_count} words. Consider refactoring."
          | recommendations
        ]
      else
        recommendations
      end

    # Check individual files
    recommendations =
      audit_results
      |> Enum.filter(& &1["oversized"])
      |> Enum.reduce(recommendations, fn file, acc ->
        [
          "#{Path.basename(file["path"])} is #{file["word_count"]} words (target: #{@target_word_count})"
          | acc
        ]
      end)

    # General recommendations
    recommendations =
      if total_words > @target_word_count do
        [
          "Move framework-specific rules to project-level files only",
          "Extract repeated patterns into skills (loaded only when invoked)",
          "Delete rules you can't remember writing",
          "Convert verbose explanations into 3-word imperatives"
          | recommendations
        ]
      else
        recommendations
      end

    Enum.reverse(recommendations)
  end

  defp list_skills(skills_dir, location) do
    if File.dir?(skills_dir) do
      skills_dir
      |> Path.join("*")
      |> Path.wildcard()
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(fn skill_path ->
        skill_name = Path.basename(skill_path)
        skill_file = Path.join(skill_path, "SKILL.md")

        case File.read(skill_file) do
          {:ok, content} ->
            word_count = count_words(content)
            char_count = String.length(content)

            estimated_tokens =
              max(estimate_tokens_from_words(word_count), estimate_tokens_from_chars(char_count))

            %{
              "name" => skill_name,
              "location" => location,
              "path" => skill_path,
              "word_count" => word_count,
              "char_count" => char_count,
              "estimated_tokens" => estimated_tokens
            }

          {:error, _} ->
            %{
              "name" => skill_name,
              "location" => location,
              "path" => skill_path,
              "error" => "unreadable",
              "word_count" => 0,
              "char_count" => 0,
              "estimated_tokens" => 0
            }
        end
      end)
    else
      []
    end
  end

  defp find_duplicate_skills(all_skills) do
    all_skills
    |> Enum.group_by(& &1["name"])
    |> Enum.filter(fn {_name, skills} -> length(skills) > 1 end)
    |> Enum.map(fn {name, skills} ->
      total_word_count = Enum.sum(Enum.map(skills, & &1["word_count"]))
      total_tokens = estimate_tokens_from_words(total_word_count)

      %{
        "name" => name,
        "instances" => skills,
        "count" => length(skills),
        "total_word_count" => total_word_count,
        "total_tokens" => total_tokens,
        "locations" => Enum.map(skills, & &1["location"])
      }
    end)
  end

  defp build_skill_recommendations(all_skills, duplicates) do
    recommendations = []

    # Check for duplicates
    recommendations =
      if Enum.empty?(duplicates) do
        recommendations
      else
        duplicate_count = length(duplicates)
        duplicate_tokens = Enum.sum(Enum.map(duplicates, & &1["total_tokens"]))

        [
          "Found #{duplicate_count} duplicate skill(s) wasting ~#{duplicate_tokens} tokens",
          "Remove duplicate skills from either user-level (~/.claude/skills/) or project-level (.claude/skills/ or .agents/skills/)"
          | recommendations
        ]
      end

    # Check total skill count
    recommendations =
      if length(all_skills) > 10 do
        [
          "Total of #{length(all_skills)} skills installed. Consider disabling unused skills to reduce token overhead."
          | recommendations
        ]
      else
        recommendations
      end

    # Check for oversized individual skills
    recommendations =
      all_skills
      |> Enum.filter(&(&1["word_count"] > 500))
      |> Enum.reduce(recommendations, fn skill, acc ->
        [
          "Skill '#{skill["name"]}' is #{skill["word_count"]} words (#{skill["location"]}). Consider splitting into smaller skills."
          | acc
        ]
      end)

    Enum.reverse(recommendations)
  end

  defp build_tool_recommendations(tool_measurements, total_tokens, tool_count, group_savings) do
    recommendations = []

    # Overall size assessment
    recommendations =
      if total_tokens > 50_000 do
        [
          "Total tool schema size is #{total_tokens} tokens across #{tool_count} tools. Consider lazy loading or tool filtering."
          | recommendations
        ]
      else
        recommendations
      end

    # Average size assessment
    avg_tokens = if(tool_count > 0, do: div(total_tokens, tool_count), else: 0)

    recommendations =
      if avg_tokens > 1_500 do
        [
          "Average tool schema is #{avg_tokens} tokens. Some tools may have overly complex schemas."
          | recommendations
        ]
      else
        recommendations
      end

    # Identify largest tools
    largest_tools = Enum.take(tool_measurements, 3)

    recommendations =
      Enum.reduce(largest_tools, recommendations, fn tool, acc ->
        [
          "Tool '#{tool["name"]}' is #{tool["estimated_tokens"]} tokens (largest). Consider simplifying its schema."
          | acc
        ]
      end)

    # Tool group recommendations with actionable env var hint
    recommendations =
      if group_savings["core_governance"]["savings_tokens"] > 0 do
        savings_pct = group_savings["core_governance"]["savings_percent"]
        savings_tok = group_savings["core_governance"]["savings_tokens"]

        [
          "Set CK_TOOL_GROUPS=core,governance in your MCP server env to save #{savings_tok} tokens (#{savings_pct}% reduction) per session"
          | recommendations
        ]
      else
        recommendations
      end

    # General recommendations
    recommendations =
      if tool_count > 40 do
        [
          "High tool count (#{tool_count}). Set CK_TOOL_GROUPS=core to load only essential tools and cut schema overhead by ~80%."
          | recommendations
        ]
      else
        recommendations
      end

    Enum.reverse(recommendations)
  end

  defp calculate_group_savings(tool_measurements, _available_groups) do
    # Calculate savings for common group combinations
    combinations = %{
      "core" => ["core"],
      "governance" => ["governance"],
      "core_governance" => ["core", "governance"],
      "observability" => ["observability"],
      "minimal" => ["core"]
    }

    total_tokens = Enum.sum(Enum.map(tool_measurements, & &1["estimated_tokens"]))

    Enum.map(combinations, fn {name, groups} ->
      # Get tools in these groups
      group_tool_names =
        groups
        |> Enum.flat_map(fn group -> get_group_tool_names(group) end)
        |> MapSet.new()
        |> MapSet.to_list()

      # Calculate tokens for tools in these groups
      group_tokens =
        tool_measurements
        |> Enum.filter(&(&1["name"] in group_tool_names))
        |> Enum.map(& &1["estimated_tokens"])
        |> Enum.sum()

      savings = total_tokens - group_tokens
      savings_pct = if(total_tokens > 0, do: round(savings * 100 / total_tokens), else: 0)

      {name,
       %{
         "groups" => groups,
         "tool_count" => length(group_tool_names),
         "group_tokens" => group_tokens,
         "savings_tokens" => savings,
         "savings_percent" => savings_pct
       }}
    end)
    |> Enum.into(%{})
  end

  defp get_group_tool_names(group_name) do
    # This would ideally come from Protocol, but for now define inline
    # to avoid circular dependency
    case group_name do
      "core" ->
        ["ck_validate", "ck_context", "ck_execute_code", "ck_budget", "ck_route"]

      "governance" ->
        [
          "ck_review_submit",
          "ck_review_status",
          "ck_finding",
          "ck_goal",
          "ck_memory_record",
          "ck_memory_search",
          "ck_memory_archive",
          "ck_delegate"
        ]

      "observability" ->
        [
          "ck_observability",
          "ck_experience_index",
          "ck_experience_read",
          "ck_experience_search",
          "ck_trace_packet",
          "ck_failure_clusters"
        ]

      _ ->
        []
    end
  end
end
