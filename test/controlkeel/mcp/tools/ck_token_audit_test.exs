defmodule ControlKeel.MCP.Tools.CkTokenAuditTest do
  use ExUnit.Case, async: true

  alias ControlKeel.MCP.Tools.CkTokenAudit

  @moduletag :tmp_dir

  setup do
    tmp = System.tmp_dir!() |> Path.join("ck_token_audit_test_#{:rand.uniform(999_999)}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  describe "mode: rules" do
    test "returns no_rules when no rule files exist", %{tmp: tmp} do
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      assert result["status"] == "no_rules"
      assert result["total_words"] == 0
      assert result["rule_files"] == []
    end

    test "returns optimal for small AGENTS.md", %{tmp: tmp} do
      File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 100))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      assert result["status"] == "optimal"
      assert result["total_words"] == 100
    end

    test "returns oversized for large AGENTS.md and includes recommendations", %{tmp: tmp} do
      File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 1500))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      assert result["status"] == "oversized"
      assert result["total_words"] > 1200
      assert length(result["recommendations"]) > 0
    end

    test "scans CLAUDE.md alongside AGENTS.md", %{tmp: tmp} do
      File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 600))
      File.write!(Path.join(tmp, "CLAUDE.md"), String.duplicate("word ", 700))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      assert result["total_words"] == 1300
      assert result["status"] == "oversized"
      assert length(result["rule_files"]) == 2
    end

    test "scans Cursor .mdc rule files", %{tmp: tmp} do
      rules_dir = Path.join([tmp, ".cursor", "rules"])
      File.mkdir_p!(rules_dir)
      File.write!(Path.join(rules_dir, "style.mdc"), String.duplicate("word ", 200))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      assert result["total_words"] == 200
      assert Enum.any?(result["rule_files"], &String.ends_with?(&1["path"], "style.mdc"))
    end

    test "scans Windsurf rule files", %{tmp: tmp} do
      rules_dir = Path.join([tmp, ".windsurf", "rules"])
      File.mkdir_p!(rules_dir)
      File.write!(Path.join(rules_dir, "main.md"), String.duplicate("word ", 150))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      assert result["total_words"] == 150
    end

    test "scans GitHub Copilot instructions", %{tmp: tmp} do
      github_dir = Path.join(tmp, ".github")
      File.mkdir_p!(github_dir)

      File.write!(
        Path.join(github_dir, "copilot-instructions.md"),
        String.duplicate("word ", 400)
      )

      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      assert result["total_words"] == 400
    end

    test "deduplicates identical file paths", %{tmp: tmp} do
      File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 100))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "rules", "project_root" => tmp})
      paths = Enum.map(result["rule_files"], & &1["path"])
      assert length(paths) == length(Enum.uniq(paths))
    end
  end

  describe "mode: skills" do
    test "result includes skills list and duplicate fields", %{tmp: tmp} do
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "skills", "project_root" => tmp})
      assert is_list(result["skills"])
      assert is_list(result["duplicates"])
      assert is_integer(result["duplicate_token_count"])
      assert is_integer(result["total_skill_words"])
    end

    test "detects skills in project .claude/skills", %{tmp: tmp} do
      skill_dir = Path.join([tmp, ".claude", "skills", "unique-test-#{:rand.uniform(999_999)}"])
      File.mkdir_p!(skill_dir)
      skill_name = Path.basename(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), String.duplicate("word ", 100))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "skills", "project_root" => tmp})
      assert Enum.any?(result["skills"], &(&1["name"] == skill_name))
    end

    test "detects skills in project .agents/skills", %{tmp: tmp} do
      skill_name = "agents-test-#{:rand.uniform(999_999)}"
      skill_dir = Path.join([tmp, ".agents", "skills", skill_name])
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), String.duplicate("word ", 50))
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "skills", "project_root" => tmp})
      assert Enum.any?(result["skills"], &(&1["name"] == skill_name))
    end

    test "detects duplicate skills across project dirs and calculates wasted tokens", %{tmp: tmp} do
      skill_name = "shared-#{:rand.uniform(999_999)}"

      for subdir <- [".claude/skills", ".agents/skills", ".codex/skills"] do
        skill_dir = Path.join([tmp, subdir, skill_name])
        File.mkdir_p!(skill_dir)
        File.write!(Path.join(skill_dir, "SKILL.md"), String.duplicate("word ", 100))
      end

      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "skills", "project_root" => tmp})

      assert result["project_root"] == tmp
      assert result["estimated_tokens"] == result["total_skill_tokens"]

      project_dups = Enum.filter(result["duplicates"], &(&1["name"] == skill_name))
      assert length(project_dups) == 1
      dup = hd(project_dups)
      assert dup["count"] >= 3
      assert result["duplicate_word_count"] > 0
      assert result["duplicate_token_count"] > 0
    end

    test "scans additional project skill dirs: .roo, .cline, .github, .cursor", %{tmp: tmp} do
      skill_name = "multi-#{:rand.uniform(999_999)}"

      for subdir <- [".roo/skills", ".cline/skills", ".github/skills", ".cursor/skills"] do
        skill_dir = Path.join([tmp, subdir, skill_name])
        File.mkdir_p!(skill_dir)
        File.write!(Path.join(skill_dir, "SKILL.md"), "# skill\nsome content")
      end

      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "skills", "project_root" => tmp})
      matching = Enum.filter(result["skills"], &(&1["name"] == skill_name))
      assert length(matching) >= 4
    end
  end

  describe "mode: full" do
    test "merges rules and skills audit", %{tmp: tmp} do
      File.write!(Path.join(tmp, "AGENTS.md"), String.duplicate("word ", 1500))
      skill_dir = Path.join([tmp, ".claude", "skills", "test-skill"])
      File.mkdir_p!(skill_dir)
      File.write!(Path.join(skill_dir, "SKILL.md"), String.duplicate("word ", 200))

      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "full", "project_root" => tmp})
      assert result["status"] == "oversized"
      assert is_list(result["skills"])
      assert is_list(result["skill_recommendations"])
      assert is_integer(result["duplicate_token_count"])
      assert result["rule_tokens"] > 0
      assert result["estimated_tokens"] == result["rule_tokens"] + result["total_skill_tokens"]
    end

    test "defaults to full mode when mode is omitted", %{tmp: tmp} do
      assert {:ok, result} = CkTokenAudit.call(%{"project_root" => tmp})
      assert Map.has_key?(result, "rule_files")
      assert Map.has_key?(result, "skills")
    end
  end

  describe "mode: tools" do
    test "returns all CK tool schemas with token estimates" do
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "tools"})
      assert result["tool_count"] > 0
      assert result["total_tokens"] > 0
      assert is_list(result["tools"])
      assert is_list(result["recommendations"])
      assert is_map(result["group_savings"])
    end

    test "group_savings includes core_governance combination" do
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "tools"})
      assert Map.has_key?(result["group_savings"], "core_governance")
      savings = result["group_savings"]["core_governance"]
      assert savings["savings_tokens"] > 0
      assert savings["savings_percent"] > 0
    end

    test "recommendations mention CK_TOOL_GROUPS env var" do
      assert {:ok, result} = CkTokenAudit.call(%{"mode" => "tools"})
      all_recs = Enum.join(result["recommendations"], " ")
      assert String.contains?(all_recs, "CK_TOOL_GROUPS")
    end
  end

  describe "error handling" do
    test "returns error for invalid mode" do
      assert {:error, {:invalid_arguments, _}} =
               CkTokenAudit.call(%{"mode" => "invalid"})
    end

    test "returns error when arguments are not a map" do
      assert {:error, {:invalid_arguments, _}} = CkTokenAudit.call("bad input")
    end
  end
end
